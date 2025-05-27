# Secrets Template

This document provides detailed information about the Secrets template available in the Terragrunt GCP infrastructure.

## Overview

The Secrets template (`_common/templates/secret_manager.hcl`) provides a standardized approach to deploying Google Cloud Secret Manager secrets using the [terraform-google-secret-manager](https://github.com/GoogleCloudPlatform/terraform-google-secret-manager) module. It ensures consistent secret management, proper access controls, and environment-aware configuration.

## Features

- Environment-aware secret configuration
- Standardized secret creation and versioning
- IAM access control management
- Automatic replication configuration
- Secret rotation and lifecycle management
- Consistent labeling and organization

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `project_id` | GCP project ID | `"project-id"` |
| `secrets` | List of secrets to create | See secret configuration |

### Optional Parameters with Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `replication` | `"automatic"` | Secret replication policy |
| `secret_data` | `{}` | Initial secret values |
| `secret_bindings` | `{}` | IAM bindings for secrets |
| `labels` | See template | Resource labels |

## Usage

## Directory Structure

Secret configurations are organized within the environment directories following this pattern:

```
live/
└── non-production/
    └── development/
        └── dev-01/
            └── secrets/
                ├── secrets.hcl               # Common secret configuration
                ├── app-api-key/              # Individual secret
                │   └── terragrunt.hcl
                ├── db-connection-string/
                │   └── terragrunt.hcl
                ├── service-account-key/
                │   └── terragrunt.hcl
                └── oauth-client-secret/
                    └── terragrunt.hcl
```

### Basic Implementation

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "secret_manager_template" {
  path = "${get_parent_terragrunt_dir()}/_common/templates/secret_manager.hcl"
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
  merged_vars = merge(
    try(read_terragrunt_config(find_in_parent_folders("account.hcl")).locals, {}),
    try(read_terragrunt_config(find_in_parent_folders("env.hcl")).locals, {}),
    try(read_terragrunt_config(find_in_parent_folders("project.hcl")).locals, {}),
    try(read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals, {})
  )
  
  secret_name = basename(get_terragrunt_dir())
}

inputs = merge(
  try(read_terragrunt_config("${get_parent_terragrunt_dir()}/_common/templates/secret_manager.hcl").inputs, {}),
  local.merged_vars,
  {
    project_id = try(dependency.project.outputs.project_id, "mock-project-id")
    
    secrets = [
      {
        name        = local.secret_name
        secret_data = "initial-secret-value"
        labels = {
          environment = local.merged_vars.environment
          purpose     = "application-config"
        }
      }
    ]
    
    # IAM bindings for secret access
    secret_bindings = {
      "${local.secret_name}" = {
        members = [
          "serviceAccount:${local.merged_vars.project_service_account}"
        ]
        role = "roles/secretmanager.secretAccessor"
      }
    }
  }
)
```

### Advanced Usage

#### Multiple Secrets with Different Configurations

```hcl
inputs = merge(
  # ... other configuration ...
  {
    secrets = [
      {
        name        = "database-password"
        secret_data = "secure-password-123"
        replication = {
          user_managed = {
            replicas = [
              {
                location = "us-central1"
              },
              {
                location = "us-east1"
              }
            ]
          }
        }
      },
      {
        name        = "api-key"
        secret_data = "api-key-value"
        replication = "automatic"
      }
    ]
    
    secret_bindings = {
      "database-password" = {
        members = [
          "serviceAccount:app@project.iam.gserviceaccount.com"
        ]
        role = "roles/secretmanager.secretAccessor"
      }
      "api-key" = {
        members = [
          "serviceAccount:app@project.iam.gserviceaccount.com",
          "group:developers@example.com"
        ]
        role = "roles/secretmanager.secretAccessor"
      }
    }
  }
)
```

#### Secret Rotation Configuration

```hcl
inputs = merge(
  # ... other configuration ...
  {
    secrets = [
      {
        name        = "rotated-secret"
        secret_data = "initial-value"
        rotation = {
          auto = {
            rotation_period = "2592000s"  # 30 days
          }
        }
      }
    ]
  }
)
```

## Best Practices

1. **Least Privilege Access** - Grant minimal necessary permissions to secrets
2. **Environment Separation** - Use separate secrets for different environments
3. **Secret Rotation** - Implement regular secret rotation where appropriate
4. **Naming Conventions** - Use consistent naming for secrets
5. **Replication Strategy** - Choose appropriate replication based on requirements
6. **Monitoring** - Enable audit logging for secret access
7. **No Hardcoded Values** - Never commit actual secret values to version control

## Secret Organization

### Common Configuration Pattern

Create a `secrets.hcl` file for shared configuration:

```hcl
# Common dependencies and configuration for all secrets
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
    
    # Common labels for all secrets
    common_labels = {
      managed_by  = "terragrunt"
      environment = try(local.merged_vars.environment, "unknown")
      project     = try(local.merged_vars.project, "unknown")
    }
  }
}
```

## Deployment Order

1. **Project** → Creates the GCP project
2. **Secrets** → Creates secret definitions
3. **Applications** → Deploy applications that use secrets

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure the service account has `roles/secretmanager.admin`
   - Check IAM bindings are correctly configured

2. **Secret Not Found Errors**
   - Verify secret names match exactly
   - Check the secret exists in the correct project

3. **Replication Errors**
   - Ensure specified regions are valid
   - Check for organization policy restrictions

### Validation Commands

```bash
# List secrets
gcloud secrets list --project=PROJECT_ID

# Describe a secret
gcloud secrets describe SECRET_NAME --project=PROJECT_ID

# List secret versions
gcloud secrets versions list SECRET_NAME --project=PROJECT_ID

# Access a secret (requires permissions)
gcloud secrets versions access latest --secret=SECRET_NAME --project=PROJECT_ID
```

## Module Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `secret_ids` | Map of secret names to IDs | `{"api-key": "projects/project/secrets/api-key"}` |
| `secret_versions` | Map of secret versions | `{"api-key": "1"}` |

## Security Considerations

1. **Access Control** - Use IAM to strictly control secret access
2. **Audit Logging** - Enable audit logs for secret operations
3. **Secret Scanning** - Implement secret scanning in CI/CD pipelines
4. **Rotation Policies** - Implement regular secret rotation
5. **Backup Strategy** - Consider backup and recovery for critical secrets
6. **Encryption** - Secrets are automatically encrypted at rest

## Integration Examples

### Using Secrets in Compute Instances

```hcl
# In compute instance configuration
metadata = {
  startup-script = <<-EOT
    #!/bin/bash
    SECRET_VALUE=$(gcloud secrets versions access latest --secret="api-key" --project="${project_id}")
    echo "SECRET_VALUE=$SECRET_VALUE" >> /etc/environment
  EOT
}
```

### Using Secrets in Kubernetes

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  api-key: <base64-encoded-value-from-secret-manager>
```

## References

- [terraform-google-secret-manager module](https://github.com/GoogleCloudPlatform/terraform-google-secret-manager)
- [Google Cloud Secret Manager documentation](https://cloud.google.com/secret-manager/docs)
- [Secret Manager Best Practices](https://cloud.google.com/secret-manager/docs/best-practices)
- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/) 
