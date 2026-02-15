# IAM Bindings Template Guide

This document provides detailed information about the IAM bindings template and configuration pattern for compute instances in the Terragrunt GCP infrastructure.

## Overview

The IAM bindings template (`_common/templates/iam_bindings.hcl`) provides a standardized approach to managing IAM permissions for compute instances that use dedicated service accounts. This pattern enables least-privilege access by granting only the necessary permissions to each instance's service account, rather than using broadly-scoped project service accounts.

## Architecture

The IAM bindings pattern follows this workflow:

1. **Instance Template**: Creates a dedicated service account for the compute instance
2. **IAM Bindings**: Grants specific IAM roles to the dedicated service account
3. **Dependency Management**: IAM bindings depend on the instance template to retrieve the service account

Benefits:
- **Security**: Least-privilege access with dedicated service accounts
- **Isolation**: Each instance has its own service account and permissions
- **Auditability**: Clear permission tracking per instance
- **Maintainability**: Centralized IAM role management per instance type

## Directory Structure

```
compute/
├── instance-name/
│   ├── terragrunt.hcl              # Instance template (creates service account)
│   ├── iam-bindings/
│   │   └── terragrunt.hcl          # IAM bindings for instance service account
│   └── vm/
│       └── terragrunt.hcl          # Compute instance (uses template)
```

## Configuration Pattern

### 1. Instance Template Configuration

First, configure the instance template to create a dedicated service account:

```hcl
inputs = {
  # Create a dedicated service account for this instance
  create_service_account = true
  
  # Service account must be null for the module to create a new one
  service_account = null
  
  # Other instance template configuration...
}
```

### 2. IAM Bindings Configuration

Create IAM bindings that depend on the instance template:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "iam_template" {
  path           = "${get_repo_root()}/_common/templates/iam_bindings.hcl"
  merge_strategy = "deep"
}

# Dependency on the project
dependency "project" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

# Dependency on the instance template to get the service account
dependency "instance_template" {
  config_path = "../"
  mock_outputs = {
    service_account_info = {
      email  = "mock-instance@mock-project-id.iam.gserviceaccount.com"
      id     = "mock-instance"
      member = "serviceAccount:mock-instance@mock-project-id.iam.gserviceaccount.com"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  projects = [dependency.project.outputs.project_id]
  mode     = "additive"

  bindings = {
    # Example: Grant specific roles to the instance service account
    "roles/secretmanager.secretAccessor" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
    
    "roles/storage.objectAdmin" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
    
    "roles/logging.logWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
    
    "roles/monitoring.metricWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
  }
}
```

## Common IAM Roles by Use Case

### Web Server Instance
```hcl
bindings = {
  # Access to application secrets in Secret Manager
  "roles/secretmanager.secretAccessor" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Access to application storage bucket
  "roles/storage.objectAdmin" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Self-management capabilities (shutdown after sync)
  "roles/compute.instanceAdmin.v1" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Monitoring and logging
  "roles/logging.logWriter" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  "roles/monitoring.metricWriter" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]
}
```

### SQL Server Instance
```hcl
bindings = {
  # Access to SQL Server admin/DBA passwords
  "roles/secretmanager.secretAccessor" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Access to backup storage bucket
  "roles/storage.objectAdmin" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Monitoring and logging
  "roles/logging.logWriter" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  "roles/monitoring.metricWriter" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]
}
```

### Web Application Instance
```hcl
bindings = {
  # Read access to application secrets
  "roles/secretmanager.secretAccessor" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Read access to static assets bucket
  "roles/storage.objectViewer" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Database connection (if using Cloud SQL)
  "roles/cloudsql.client" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  # Monitoring and logging
  "roles/logging.logWriter" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]

  "roles/monitoring.metricWriter" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]
}
```

## Dependencies and Mock Outputs

### Instance Template Dependency

The IAM bindings must depend on the instance template to get the created service account:

```hcl
dependency "instance_template" {
  config_path = "../"
  mock_outputs = {
    service_account_info = {
      email  = "mock-service-account@mock-project-id.iam.gserviceaccount.com"
      id     = "mock-service-account"
      member = "serviceAccount:mock-service-account@mock-project-id.iam.gserviceaccount.com"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}
```

**Important**: The mock outputs must match the structure provided by the terraform-google-vm module's `service_account_info` output.

### Project Dependency

Always include a dependency on the project to get the project ID:

```hcl
dependency "project" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}
```

## Service Account vs Project Service Account

### Dedicated Service Account (Recommended)
```hcl
# In instance template
inputs = {
  create_service_account = true
  service_account = null
}
```

Benefits:
- **Least Privilege**: Only grant permissions needed for specific instance
- **Security Isolation**: Compromised instance doesn't affect other resources
- **Auditability**: Clear tracking of which instance performed which actions
- **Compliance**: Better alignment with security best practices

### Shared Project Service Account (Legacy)
```hcl
# In instance template
inputs = {
  service_account = {
    email = dependency.project.outputs.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
```

Drawbacks:
- **Over-privileged**: Project service account often has broader permissions
- **Security Risk**: All instances share the same identity
- **Audit Complexity**: Difficult to track which instance performed actions
- **Blast Radius**: Compromise affects all instances using the same service account

## Best Practices

### 1. Use Dedicated Service Accounts
Always create dedicated service accounts for compute instances rather than using shared project service accounts.

### 2. Apply Least Privilege
Grant only the minimum IAM roles required for the instance to function:
- Start with no permissions
- Add roles one by one based on actual requirements
- Regularly review and remove unused permissions

### 3. Use Specific Roles
Prefer specific roles over broad ones:
- Use `roles/storage.objectViewer` instead of `roles/storage.admin` for read-only access
- Use `roles/secretmanager.secretAccessor` instead of `roles/secretmanager.admin`
- Avoid `roles/editor` or `roles/owner` unless absolutely necessary

### 4. Organize by Function
Group IAM roles by their purpose:
```hcl
bindings = {
  # Secret access
  "roles/secretmanager.secretAccessor" = [...]
  
  # Storage access
  "roles/storage.objectAdmin" = [...]
  
  # Infrastructure management
  "roles/compute.instanceAdmin.v1" = [...]
  
  # Observability
  "roles/logging.logWriter" = [...]
  "roles/monitoring.metricWriter" = [...]
}
```

### 5. Document Role Purpose
Add comments explaining why each role is needed:
```hcl
bindings = {
  # Grant Secret Manager access for retrieving database passwords
  "roles/secretmanager.secretAccessor" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]
  
  # Grant Storage access for backup operations
  "roles/storage.objectAdmin" = [
    "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
  ]
}
```

### 6. Use Additive Mode
Always use `mode = "additive"` to avoid conflicts with existing IAM bindings:
```hcl
inputs = {
  projects = [dependency.project.outputs.project_id]
  mode     = "additive"  # Recommended
  bindings = { ... }
}
```

## Deployment Order

The IAM bindings must be deployed in the correct order:

1. **Project** → Creates the GCP project
2. **Instance Template** → Creates the instance template and service account
3. **IAM Bindings** → Grants permissions to the service account
4. **Compute Instance** → Creates the VM using the template and service account

## Troubleshooting

### Common Issues

1. **Service Account Not Found**
   ```
   Error: The service account does not exist
   ```
   - Ensure the instance template is deployed before IAM bindings
   - Check that `create_service_account = true` is set in the instance template
   - Verify the dependency path is correct

2. **Permission Denied**
   ```
   Error: The caller does not have permission to access the service account
   ```
   - Ensure your deployment service account has `roles/iam.serviceAccountAdmin`
   - Check that the project ID is correct in the dependency

3. **Mock Output Mismatch**
   ```
   Error: service_account_info attribute does not exist
   ```
   - Update mock outputs to match the terraform-google-vm module structure
   - Ensure `service_account_info` is used instead of `service_account`

4. **Circular Dependencies**
   ```
   Error: Cycle detected in dependency graph
   ```
   - Ensure IAM bindings depend on instance template, not vice versa
   - Check that compute instance depends on instance template, not IAM bindings

### Validation Commands

```bash
# List service accounts
gcloud iam service-accounts list --project=PROJECT_ID

# List IAM bindings for a project
gcloud projects get-iam-policy PROJECT_ID

# Check specific service account permissions
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:SERVICE_ACCOUNT_EMAIL"

# Test service account impersonation
gcloud auth activate-service-account SERVICE_ACCOUNT_EMAIL \
  --key-file=PATH_TO_KEY
```

## Module Integration

### With Terraform Google VM Module

The IAM bindings template works with the terraform-google-vm module's instance_template submodule:

```hcl
# In instance template
include "instance_template" {
  path = "${get_repo_root()}/_common/templates/instance_template.hcl"
}

inputs = {
  create_service_account = true
  service_account = null
  # Other configuration...
}
```

### With IAM Module

The template uses the terraform-google-iam module for managing bindings:

```hcl
include "iam_template" {
  path = "${get_repo_root()}/_common/templates/iam_bindings.hcl"
}
```

## Security Considerations

### 1. Service Account Key Management
- Never download service account keys
- Use workload identity federation when possible
- Rotate service accounts regularly in case of compromise

### 2. Role Assignment Review
- Regularly audit IAM bindings using Cloud Asset Inventory
- Remove unused or overly broad permissions
- Use IAM Recommender to identify excessive permissions

### 3. Monitoring and Alerting
- Monitor service account usage with Cloud Logging
- Set up alerts for unusual API usage patterns
- Use Cloud Security Command Center for security insights

## References

- [terraform-google-vm module](https://github.com/terraform-google-modules/terraform-google-vm)
- [terraform-google-iam module](https://github.com/terraform-google-modules/terraform-google-iam)
- [Google Cloud IAM documentation](https://cloud.google.com/iam/docs)
- [IAM best practices](https://cloud.google.com/iam/docs/using-iam-securely)
- [Service account best practices](https://cloud.google.com/iam/docs/best-practices-service-accounts)
