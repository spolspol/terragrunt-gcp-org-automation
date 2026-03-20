# Service Accounts Template

The Service Account template (`_common/templates/service_account.hcl`) wraps `terraform-google-modules/terraform-google-service-accounts//modules/simple-sa` v4.7.0 and standardises how this repo creates project-level service accounts. Each SA gets its own directory (one SA per directory), similar to secrets and buckets.

For **GKE Workload Identity** GSAs, use the dedicated [Workload Identity Template](./WORKLOAD_IDENTITY_TEMPLATE.md) instead -- it creates both the GSA and the WI IAM binding in one resource.

Guiding principles:
- **No keys** -- prefer Workload Identity, metadata server, or approved key-management patterns.
- **Least privilege** -- manage IAM permissions in `iam-bindings/` rather than `project_roles` on the SA module.
- **Directory-based naming** -- SA name is derived from the directory name via `basename(get_terragrunt_dir())`.

## Template Location

| Item | Path |
|------|------|
| Template | `_common/templates/service_account.hcl` |
| Version pin | `_common/common.hcl` (`module_versions.service_accounts` = v4.7.0) |
| Per-project config | `live/**/iam-service-accounts/service-accounts.hcl` |
| Individual SAs | `live/**/iam-service-accounts/<sa-name>/terragrunt.hcl` |

## Directory Structure

```
live/<account>/<environment>/<project>/
├── project/
├── iam-service-accounts/
│   ├── service-accounts.hcl           # common config
│   ├── vpn-server/
│   │   └── terragrunt.hcl
│   └── pipeline-sa/
│       └── terragrunt.hcl
└── iam-bindings/                      # preferred place for permissions
    └── terragrunt.hcl
```

## Module Inputs

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | - | Service account name (SA ID) |
| `project_id` | string | Yes | - | Project where SA will be created |
| `display_name` | string | No | `"Terraform-managed service account"` | Display name |
| `description` | string | No | `""` | Description |
| `project_roles` | list(string) | No | `[]` | Roles to grant in the project |

## Module Outputs

| Output | Format | Use Case |
|--------|--------|----------|
| `email` | `name@project.iam.gserviceaccount.com` | Display, logging |
| `iam_email` | `serviceAccount:name@project.iam.gserviceaccount.com` | **IAM bindings (always use this)** |
| `name` | `projects/project/serviceAccounts/email` | Full resource name for API calls |
| `unique_id` | `123456789012345678901` | Immutable numeric identifier |

> **Important**: The `member` output does **not** exist in the `simple-sa` module. Always use `iam_email` for IAM binding member fields.

## Basic Usage

```hcl
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
}
```

## Referencing SAs From Other Resources

```hcl
dependency "vpn_server_sa" {
  config_path = "../../../iam-service-accounts/vpn-server"
  mock_outputs = {
    email     = "vpn-server@mock-project-id.iam.gserviceaccount.com"
    iam_email = "serviceAccount:vpn-server@mock-project-id.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# In IAM bindings -- always use iam_email
inputs = {
  bindings = {
    "roles/storage.objectViewer" = [
      dependency.vpn_server_sa.outputs.iam_email
    ]
  }
}
```

## CI/CD Integration

| Setting | Value |
|---------|-------|
| Resource type | `project-iam-service-accounts` |
| Path pattern | `live/**/iam-service-accounts/*/**` |
| Exclude pattern | `live/**/iam-service-accounts/*.hcl` |
| Config file | `.github/workflow-config/resource-definitions.yml` |

## Best Practices

- Keep "who exists" (service accounts) separate from "what can it do" (IAM bindings).
- Never generate keys -- prefer Workload Identity or metadata server.
- Name the directory to match the desired SA ID exactly.
- Use `iam_email` (not `email`) when referencing SAs in IAM binding member fields.
- Grant permissions via `iam-bindings/` for visibility; use `project_roles` only for simple cases.

## Troubleshooting

| Error | Cause | Resolution |
|-------|-------|------------|
| `Unsupported argument` | `simple-sa` submodule has fewer inputs than root module | Check module docs for supported inputs |
| `Account ID conflict` | Directory name does not match desired SA ID | Rename directory to match |
| State migration issues | Moving from old multi-SA pattern | Use `terragrunt import` or move state |

## References

- [terraform-google-service-accounts](https://github.com/terraform-google-modules/terraform-google-service-accounts)
- [Workload Identity Template](./WORKLOAD_IDENTITY_TEMPLATE.md)
- [Configuration Templates Overview](CONFIGURATION_TEMPLATES.md)
