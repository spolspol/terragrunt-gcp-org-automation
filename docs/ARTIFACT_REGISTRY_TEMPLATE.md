<!-- Space: PE -->
<!-- Title: Artifact Registry Template -->
<!-- Parent: Storage & Data -->
<!-- Label: template -->
<!-- Label: artifact-registry -->
<!-- Label: container-registry -->
<!-- Label: howto -->
<!-- Label: intermediate -->

# Artifact Registry Template

This document describes the Artifact Registry Terragrunt template for deploying container and artifact registries consistently across environments.

## Overview

The Artifact Registry template lives at `_common/templates/artifact_registry.hcl` and uses the official [GoogleCloudPlatform/terraform-google-artifact-registry](https://github.com/GoogleCloudPlatform/terraform-google-artifact-registry) module v0.8.2. It provides standardised defaults for repository format, mode, cleanup policies, and labelling while keeping repository-specific configuration in each Terragrunt unit.

Supported formats: DOCKER, NPM, PYTHON, MAVEN, APT, YUM, GO.

Supported modes: `STANDARD_REPOSITORY`, `REMOTE_REPOSITORY`, `VIRTUAL_REPOSITORY`.

## Template Location

```
_common/templates/artifact_registry.hcl
```

## Module Source

```
git::https://github.com/GoogleCloudPlatform/terraform-google-artifact-registry.git//?ref=v0.8.2
```

Version pinned in `_common/common.hcl` as `module_versions.artifact_registry`.

## Required Inputs

| Input | Type | Description | Example |
|-------|------|-------------|---------|
| `project_id` | string | GCP project ID | `"fn-dev-01-a"` |
| `repository_id` | string | Repository name | `"org-api-orchestrations"` |

## Optional Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `location` | string | `"europe-west2"` | GCP region for the repository |
| `format` | string | `"DOCKER"` | Repository format (DOCKER, NPM, PYTHON, MAVEN, APT, YUM, GO) |
| `mode` | string | `"STANDARD_REPOSITORY"` | Repository mode |
| `description` | string | `""` | Human-readable description |
| `docker_config` | object | `null` | Docker-specific settings (e.g. immutable tags) |
| `maven_config` | object | `null` | Maven-specific settings |
| `remote_repository_config` | object | `null` | Remote proxy configuration |
| `virtual_repository_config` | object | `null` | Virtual aggregation configuration |
| `members` | map | `{}` | IAM members (`readers`, `writers`) |
| `cleanup_policies` | map | `{}` | Automatic artifact cleanup rules |
| `cleanup_policy_dry_run` | bool | `false` | Run cleanup in dry-run mode |
| `kms_key_name` | string | `null` | CMEK encryption key |
| `labels` | map | `{ managed_by = "terragrunt", component = "artifact-registry" }` | Resource labels |

## Basic Usage -- Standard Docker Registry

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "artifact_registry_template" {
  path           = "${get_repo_root()}/_common/templates/artifact_registry.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Only resource-specific overrides needed -- template defaults auto-merged
inputs = {
  project_id    = dependency.project.outputs.project_id
  repository_id = "docker-main"
  format        = "DOCKER"
  description   = "Main Docker registry for container images"

  members = {
    readers = ["serviceAccount:cloud-run-sa@project.iam.gserviceaccount.com"]
    writers = ["serviceAccount:ci-cd-sa@project.iam.gserviceaccount.com"]
  }

  labels = {
    managed_by = "terragrunt"
    component  = "artifact-registry"
    purpose    = "container-images"
  }
}
```

## Common Patterns

### Standard Docker Registry (default)

The simplest use case -- a standard Docker repository for storing container images built by CI/CD pipelines.

```hcl
inputs = {
  project_id    = dependency.project.outputs.project_id
  repository_id = "my-app-images"
  format        = "DOCKER"
  description   = "Application container images"
}
```

### Remote Repository (GHCR Proxy)

Proxies container images from an external registry (e.g. GitHub Container Registry) and caches them locally. This is the pattern used by `org-api-orchestrations` in `fn-dev-01`:

```hcl
inputs = {
  project_id    = dependency.project.outputs.project_id
  repository_id = "org-api-orchestrations"
  location      = "europe-west2"
  format        = "DOCKER"
  description   = "Remote proxy for ghcr.io - API orchestration container images"

  # Remote repository mode - proxy to GitHub Container Registry
  mode = "REMOTE_REPOSITORY"

  remote_repository_config = {
    description = "Remote proxy for ghcr.io"
      docker_repository = {
        custom_repository = {
          uri = "https://ghcr.io"
        }
      }
      upstream_credentials = {
        username                = "ci-user"
        password_secret_version = "projects/${dependency.project.outputs.project_id}/secrets/cr-github-ghcr/versions/latest" #pragma: allowlist secret
      }
    }

  labels = {
    managed_by  = "terragrunt"
    component   = "artifact-registry"
    purpose     = "container-registry-proxy"
    upstream    = "ghcr-io"
  }
}
```

Key points for remote repositories:
- Set `mode = "REMOTE_REPOSITORY"` to enable proxying.
- Use `upstream_credentials` with a Secret Manager version reference for authentication.
- The `custom_repository.uri` points to the upstream registry (e.g. `https://ghcr.io`).

### Virtual Repository (Aggregation)

A virtual repository aggregates multiple upstream repositories behind a single endpoint, allowing consumers to pull from one location:

```hcl
inputs = {
  project_id    = dependency.project.outputs.project_id
  repository_id = "docker-virtual"
  format        = "DOCKER"
  description   = "Virtual Docker registry aggregating standard and remote repos"

  mode = "VIRTUAL_REPOSITORY"

  virtual_repository_config = {
    upstream_policies = [
      {
        id         = "standard-first"
        repository = "projects/PROJECT/locations/europe-west2/repositories/docker-main"
        priority   = 10
      },
      {
        id         = "remote-fallback"
        repository = "projects/PROJECT/locations/europe-west2/repositories/ghcr-proxy"
        priority   = 20
      }
    ]
  }
}
```

## Environment-Specific Cleanup Policies

The template provides pre-built cleanup policy sets for different environments:

| Environment | Policy | Action | Condition |
|-------------|--------|--------|-----------|
| Production | `keep-tagged` | KEEP | `tag_state = "TAGGED"` |
| Production | `delete-untagged` | DELETE | `tag_state = "UNTAGGED"`, `older_than = "604800s"` (7 days) |
| Non-production | `delete-old-untagged` | DELETE | `tag_state = "UNTAGGED"`, `older_than = "86400s"` (1 day) |

To apply cleanup policies, reference the template locals:

```hcl
inputs = {
  project_id       = dependency.project.outputs.project_id
  repository_id    = "my-app"
  cleanup_policies = include.artifact_registry_template.locals.env_configs["non-production"].cleanup_policies
}
```

## CI/CD Integration

| Setting | Value |
|---------|-------|
| Resource type | `artifact-registry` |
| Dependencies | `projects` |
| Path pattern | `live/**/artifact-registry/**` |
| Config file | `.github/workflow-config/resource-definitions.yml` |

The resource is automatically detected and deployed by the IaC Engine workflow when changes are merged to `main`.

## Importing Existing Repositories

If the repository already exists in GCP, import it before applying:

```bash
cd live/non-production/uat/functions/fn-dev-01/artifact-registry/org-api-orchestrations

terragrunt run import google_artifact_registry_repository.main \
  projects/fn-dev-01-a/locations/europe-west2/repositories/org-api-orchestrations
```

## Best Practices

- Use **remote proxy** mode for external registries to cache images locally and avoid rate limits.
- Enable **cleanup policies** to control storage costs -- use the template's environment-specific presets.
- Store upstream credentials in **Secret Manager** and reference by version path.
- Enable **immutable tags** in production to prevent image overwrites.
- Set `cleanup_policy_dry_run = true` first to verify which artefacts would be removed.
- Always apply consistent **labels** for cost tracking and resource management.

## Troubleshooting

### Import Command for Existing Repositories

```bash
terragrunt run import google_artifact_registry_repository.main \
  projects/PROJECT_ID/locations/REGION/repositories/REPO_ID
```

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| `Repository already exists` | Resource exists in GCP but not in state | Import the resource (see above) |
| `Permission denied on secret` | Upstream credentials secret inaccessible | Grant `secretmanager.secretAccessor` to the AR service agent |
| `Invalid format for mode` | Mode/format mismatch | Remote and virtual repositories must match the upstream format |

## References

- [Artifact Registry documentation](https://cloud.google.com/artifact-registry/docs)
- [terraform-google-artifact-registry module](https://github.com/GoogleCloudPlatform/terraform-google-artifact-registry)
- [Configuration Templates Overview](CONFIGURATION_TEMPLATES.md)
