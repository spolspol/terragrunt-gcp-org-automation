<!-- Space: PE -->
<!-- Title: Service Accounts Template -->
<!-- Parent: Foundation Resources -->
<!-- Label: template -->
<!-- Label: service-account -->
<!-- Label: iam -->
<!-- Label: security -->
<!-- Label: howto -->
<!-- Label: intermediate -->

# Service Accounts Template Guide

This document describes the Service Account template used to create Google Cloud service accounts with Terragrunt.

## Overview

The Service Account template (`_common/templates/service_account.hcl`) wraps the upstream module `terraform-google-modules/terraform-google-service-accounts//modules/simple-sa` and standardizes how this repo creates project service accounts.

**Key Change (2025-01)**: Service accounts now use an **individual directory pattern** (one SA per directory), similar to secrets and buckets.

Use this when you need **project-level** service accounts for automation identities, VM instance service accounts created outside the compute module, etc.

> **Note**: For **GKE Workload Identity** GSAs (pods impersonating GCP service accounts), use the dedicated [Workload Identity Template](./WORKLOAD_IDENTITY_TEMPLATE.md) instead. It uses the GKE workload-identity submodule which creates both the GSA and the WI IAM binding in one resource.

Guiding principles:
- **No keys**: avoid generating keys (prefer Workload Identity, metadata server, or approved key-management patterns).
- **Least privilege**: prefer managing IAM permissions in `iam-bindings/` rather than `project_roles` on the service-accounts module.
- **Directory-based naming**: SA name is derived from the directory name automatically.

## Where It Lives

- Template: `_common/templates/service_account.hcl` (singular)
- Version pin: `_common/common.hcl` (`module_versions.service_accounts` = v4.7.0)
- Per-project common config: `live/**/iam-service-accounts/service-accounts.hcl`
- Individual SAs: `live/**/iam-service-accounts/<sa-name>/terragrunt.hcl`

## CI / Workflow Integration

The IaC Engine treats service accounts as a dedicated resource type:
- Resource type: `project-iam-service-accounts`
- Path pattern: `live/**/iam-service-accounts/*/**`
- Exclude pattern: `live/**/iam-service-accounts/*.hcl` (excludes common config files)

If a PR changes `iam-service-accounts` directories or the shared template, CI will validate/apply these resources (depending on PR vs `main` push) in dependency order.

## Directory Structure

New individual directory pattern (similar to secrets):

```
live/<account>/<environment>/<project>/
├── project/                           # project creation (dependency)
├── iam-service-accounts/              # service accounts directory
│   ├── service-accounts.hcl           # common config (include in child dirs)
│   ├── vpn-server/                    # individual SA
│   │   └── terragrunt.hcl
│   ├── pipeline-sa/                   # another SA
│   │   └── terragrunt.hcl
│   └── gke-workload-sa/              # GKE workload identity SA
│       └── terragrunt.hcl
└── iam-bindings/                      # project IAM (preferred place for permissions)
    └── terragrunt.hcl
```

## Configuration Pattern

### Common Config: `iam-service-accounts/service-accounts.hcl`

```hcl
# Common service account configuration for all SAs in this project
# Include this in individual SA directories: find_in_parent_folders("service-accounts.hcl")

locals {
  # Common dependencies that all service accounts need
  common_dependencies = {
    project_path = "../project"
  }

  # Common mock outputs for dependencies
  common_mock_outputs = {
    project = {
      project_id = "mock-project-id"
    }
  }

  # Common labels that apply to all service accounts
  common_sa_labels = {
    component   = "service-account"
    managed_by  = "terragrunt"
    environment = "development"
    project     = "dp-dev-01"
  }

  # Environment-specific settings for service accounts
  environment_sa_settings = {
    production = {
      generate_keys = false
    }
    non-production = {
      generate_keys = false
    }
  }
}
```

### Individual SA: `iam-service-accounts/<sa-name>/terragrunt.hcl`

```hcl
# Example Service Account
# Directory name becomes the SA name: example-sa

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "service_account_template" {
  path           = "${get_repo_root()}/_common/templates/service_account.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  sa_name = basename(get_terragrunt_dir())
}

inputs = {
  project_id   = dependency.project.outputs.project_id
  name         = local.sa_name
  display_name = "Example Service Account"
  description  = "Example SA managed by Terragrunt"

  # Optional: Grant roles directly (prefer iam-bindings/ for complex setups)
  # project_roles = [
  #   "roles/logging.logWriter",
  #   "roles/monitoring.metricWriter",
  # ]
}
```

### Naming Notes

- SA name is automatically derived from the directory name via `basename(get_terragrunt_dir())`
- The `simple-sa` submodule does NOT add a prefix - the name you specify is the exact SA ID
- For legacy SAs that must keep an existing ID, simply name the directory to match (e.g., `vpn-server/`)

## Managing Permissions (Recommended)

Create the service accounts in `iam-service-accounts/<sa-name>/`, then grant permissions using the IAM bindings module in `iam-bindings/` (project-level) or `compute/**/iam-bindings/` (resource-level), depending on scope.

This keeps "who exists" separate from "what can it do".

## Module Inputs

The `simple-sa` submodule accepts these inputs:

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | - | Service account name (SA ID) |
| `project_id` | string | Yes | - | Project where SA will be created |
| `display_name` | string | No | "Terraform-managed service account" | Display name |
| `description` | string | No | "" | Description |
| `project_roles` | list(string) | No | [] | Roles to grant in the project |

## Module Outputs

The `simple-sa` submodule provides these outputs:

| Output | Format | Use Case |
|--------|--------|----------|
| `email` | `name@project.iam.gserviceaccount.com` | Display, logging, email references |
| `iam_email` | `serviceAccount:name@project.iam.gserviceaccount.com` | **IAM bindings (preferred)** |
| `name` | `projects/project/serviceAccounts/email` | Full resource name |
| `unique_id` | `123456789012345678901` | Unique numeric identifier |

> **Important**: The `member` output **does not exist** in the `simple-sa` module. Always use `iam_email` for IAM binding member fields.

### When to Use Each Output

| Scenario | Output to Use | Example |
|----------|---------------|---------|
| IAM bindings member field | `iam_email` | `member = dependency.my_sa.outputs.iam_email` |
| Displaying SA email in logs | `email` | `"Service account: ${dependency.my_sa.outputs.email}"` |
| Referencing SA in GCP APIs | `name` | Full resource path for API calls |
| Tracking SA for auditing | `unique_id` | Immutable identifier |

## Referencing Service Accounts From Other Resources

### Basic Dependency Pattern

```hcl
dependency "vpn_server_sa" {
  config_path = "../../../iam-service-accounts/vpn-server"
  mock_outputs = {
    email     = "vpn-server@mock-project-id.iam.gserviceaccount.com"
    iam_email = "serviceAccount:vpn-server@mock-project-id.iam.gserviceaccount.com"
    name      = "projects/mock-project-id/serviceAccounts/vpn-server@mock-project-id.iam.gserviceaccount.com"
    unique_id = "123456789012345678901"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  vpn_sa_email = dependency.vpn_server_sa.outputs.email
}
```

### Using Service Accounts in IAM Bindings

When referencing a service account in IAM bindings, **always use `iam_email`**:

```hcl
dependency "my_sa" {
  config_path = "../../iam-service-accounts/my-service"

  mock_outputs = {
    email     = "my-service@project.iam.gserviceaccount.com"
    iam_email = "serviceAccount:my-service@project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  bindings = {
    "roles/storage.objectViewer" = [
      dependency.my_sa.outputs.iam_email  # Correct - use iam_email
    ]
  }
}
```

### Common Mistakes to Avoid

```hcl
# WRONG - 'member' output does not exist
member = dependency.my_sa.outputs.member

# WRONG - email is not in IAM format
member = dependency.my_sa.outputs.email

# WRONG - manually constructing when iam_email exists
member = "serviceAccount:${dependency.my_sa.outputs.email}"

# CORRECT - use iam_email directly
member = dependency.my_sa.outputs.iam_email
```

## Migration from Old Pattern

### Old Pattern (multi-SA in single file)

```
iam-service-accounts/
└── terragrunt.hcl   # names = ["sa1", "sa2", "sa3"]
```

### New Pattern (individual directories)

```
iam-service-accounts/
├── service-accounts.hcl   # common config
├── sa1/
│   └── terragrunt.hcl
├── sa2/
│   └── terragrunt.hcl
└── sa3/
    └── terragrunt.hcl
```

### Migration Steps

1. Note the existing SA names from the old `names = [...]` list
2. Create individual directories for each SA
3. Create `terragrunt.hcl` in each directory following the new pattern
4. Delete the old multi-SA `terragrunt.hcl` file
5. Run `terragrunt run plan` to verify state matches

## Validation / Troubleshooting

Common failures:
- **"Unsupported argument"** during plan/validate: the `simple-sa` module has fewer inputs than the root module.
- **Account ID conflicts**: ensure directory name matches the desired SA ID exactly.
- **State migration**: when migrating from old pattern, you may need to `terragrunt import` or move state.

Local validation commands (run from an individual SA directory):

```bash
terragrunt hcl fmt --check --diff
terragrunt hcl validate
terragrunt hcl validate --inputs
terragrunt run plan
```

## Module Version

- **Current**: v4.7.0 (January 2026)
- **Submodule**: `modules/simple-sa`
- **Source**: [terraform-google-modules/service-accounts](https://github.com/terraform-google-modules/terraform-google-service-accounts)
- **Releases**: [GitHub Releases](https://github.com/terraform-google-modules/terraform-google-service-accounts/releases)
