# Secrets Template

The Terragrunt template for creating Google Cloud Secret Manager resources. For the broader secret management strategy (population, rotation, access patterns), see [SECRET_MANAGEMENT.md](SECRET_MANAGEMENT.md).

**Module version**: `secret_manager = "v0.8.0"` (pinned in `_common/common.hcl`)

**Template**: `_common/templates/secret_manager.hcl` ([terraform-google-secret-manager](https://github.com/GoogleCloudPlatform/terraform-google-secret-manager))

## Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `project_id` | GCP project ID | `"project-id"` |
| `secrets` | List of secrets to create | See examples below |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `replication` | `"automatic"` | Secret replication policy |
| `secret_data` | `{}` | Initial secret values |
| `secret_bindings` | `{}` | IAM bindings for secrets |
| `labels` | See template | Resource labels |

## Directory Structure

Each secret lives in its own subfolder under `secrets/`:

```
live/non-production/development/
  platform/dp-dev-01/europe-west2/secrets/
    secrets.hcl                          # Common configuration
    gke-argocd-oauth-client-secret/
      terragrunt.hcl
    gke-github-ghcr/
      terragrunt.hcl
  functions/fn-dev-01/europe-west2/secrets/
    secrets.hcl
    cr-api-key/
      terragrunt.hcl
    cr-db-password/
      terragrunt.hcl
```

## Canonical Example

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "secret_manager_template" {
  path           = "${get_repo_root()}/_common/templates/secret_manager.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  skip_outputs = true
}

locals {
  secret_name = basename(get_terragrunt_dir())
}

inputs = {
  project_id = try(dependency.project.outputs.project_id, "mock-project-id")

  secrets = [
    {
      name        = local.secret_name
      secret_data = "initial-secret-value"
      labels = {
        environment = include.base.locals.environment
        purpose     = "application-config"
      }
    }
  ]

  secret_bindings = {
    "${local.secret_name}" = {
      members = [
        "serviceAccount:${include.base.locals.merged.project_service_account}"
      ]
      role = "roles/secretmanager.secretAccessor"
    }
  }
}
```

### User-Managed Replication

For secrets that require specific regional placement:

```hcl
secrets = [
  {
    name        = "database-password"
    secret_data = "secure-password-123"
    replication = {
      user_managed = {
        replicas = [
          { location = "us-central1" },
          { location = "us-east1" }
        ]
      }
    }
  }
]
```

### Shared Configuration (`secrets.hcl`)

Common dependencies and labels for all secrets in a project:

```hcl
dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  skip_outputs = true
}

locals {
  common_inputs = {
    project_id = try(dependency.project.outputs.project_id, "mock-project-id")
    common_labels = {
      managed_by  = "terragrunt"
      environment = try(include.base.locals.environment, "unknown")
      project     = try(include.base.locals.merged.project, "unknown")
    }
  }
}
```

## Deployment Order

1. **Project** -- creates the GCP project
2. **Secrets** -- creates secret definitions
3. **Applications** -- deploy workloads that consume secrets

## Module Outputs

| Output | Description |
|--------|-------------|
| `secret_ids` | Map of secret names to full resource IDs |
| `secret_versions` | Map of secret names to current version numbers |

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Permission errors | Ensure service account has `roles/secretmanager.admin` |
| Secret not found | Verify name matches exactly and secret exists in correct project |
| Replication errors | Check that specified regions are valid and allowed by org policy |

### Validation Commands

```bash
gcloud secrets list --project=PROJECT_ID
gcloud secrets describe SECRET_NAME --project=PROJECT_ID
gcloud secrets versions list SECRET_NAME --project=PROJECT_ID
```

## Best Practices

1. **Least privilege** -- grant only `secretAccessor` to consuming workloads
2. **Environment separation** -- use separate secrets per environment
3. **No hardcoded values** -- never commit actual secret values to version control
4. **Naming consistency** -- use `basename(get_terragrunt_dir())` for secret names
5. **Rotation** -- implement rotation policies for long-lived credentials

## References

- [terraform-google-secret-manager](https://github.com/GoogleCloudPlatform/terraform-google-secret-manager)
- [Secret Manager documentation](https://cloud.google.com/secret-manager/docs)
- [Secret Manager best practices](https://cloud.google.com/secret-manager/docs/best-practices)
