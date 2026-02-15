# Project Template

This document provides detailed information about the Project template available in the Terragrunt GCP infrastructure.

## Overview

The Project template (`_common/templates/project.hcl`) provides a standardized approach to deploying Google Cloud projects using the [terraform-google-project-factory](https://github.com/terraform-google-modules/terraform-google-project-factory) module. It ensures consistent project configuration, proper IAM setup, and environment-aware settings.

## Features

- Environment-aware project configuration
- Standardized project creation with billing association
- Automatic API enablement for required services
- IAM management and service account creation
- Budget alerts and monitoring setup
- Consistent labeling and organization

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `name` | Project name | `"dp-dev-01"` |
| `org_id` | Organization ID | `"123456789"` |
| `billing_account` | Billing account ID | `"ABCDEF-123456-789012"` |
| `folder_id` | Parent folder ID | `"folders/123456789"` |

### Optional Parameters with Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `auto_create_network` | `false` | Create default VPC network |
| `activate_apis` | See template | APIs to enable |
| `budget_amount` | Environment-specific | Monthly budget limit |
| `budget_alert_emails` | `[]` | Email addresses for budget alerts |
| `usage_bucket_name` | `null` | Centralized billing usage reports bucket |
| `usage_bucket_prefix` | Project name | Prefix for usage data in bucket |
| `labels` | See template | Project labels |

## Directory Structure

Project configurations are located within the environment directories following this pattern:

```
live/
└── non-production/
    └── development/
        └── dp-dev-01/  # Environment specific project
            └── project/     # Project configuration directory
                └── terragrunt.hcl
```

## Usage

### Basic Implementation

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "project_template" {
  path = "${get_parent_terragrunt_dir()}/_common/templates/project.hcl"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "folders/123456789"
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
}

inputs = merge(
  try(read_terragrunt_config("${get_parent_terragrunt_dir()}/_common/templates/project.hcl").inputs, {}),
  local.merged_vars,
  {
    name            = "${local.merged_vars.name_prefix}-${local.merged_vars.project_id}"
    org_id          = local.merged_vars.org_id
    billing_account = local.merged_vars.billing_account
    folder_id       = try(dependency.folder.outputs.folder_id, "folders/mock-folder-id")
    
    # Environment-specific budget
    budget_amount = local.merged_vars.environment_type == "production" ? 1000 : 100
    
    budget_alert_emails = [
      "finance@example.com",
      "devops@example.com"
    ]
    
    labels = merge(
      {
        component   = "project"
        environment = local.merged_vars.environment
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {})
    )
  }
)
```

### Advanced Usage

#### Custom API Activation

```hcl
inputs = merge(
  # ... other configuration ...
  {
    activate_apis = [
      "compute.googleapis.com",
      "container.googleapis.com",
      "bigquery.googleapis.com",
      "cloudsql.googleapis.com",
      "secretmanager.googleapis.com"
    ]
  }
)
```

#### Service Account Creation

```hcl
inputs = merge(
  # ... other configuration ...
  {
    create_project_sa = true
    project_sa_name   = "terraform-sa"
  }
)
```

#### Billing Usage Reports Configuration

Projects can be configured to export usage data to a centralized billing bucket for cost analysis:

```hcl
inputs = merge(
  # ... other configuration ...
  {
    # Centralized billing data collection
    usage_bucket_name   = "org-billing-usage-reports"  # Centralized bucket
    usage_bucket_prefix = "my-project"                    # Project-specific prefix
  }
)
```

**Benefits of Centralized Billing:**
- Organization-wide cost analysis and optimization
- Simplified billing data management
- Consistent billing data format across projects
- Reduced storage costs

**Configuration Inheritance:**
The billing bucket configuration typically inherits from environment settings:
```hcl
locals {
  environment_usage_bucket_name = "org-billing-usage-reports"
}

inputs = {
  usage_bucket_name   = local.environment_usage_bucket_name
  usage_bucket_prefix = local.base_project_name
}
```

## Best Practices

1. **Consistent Naming** - Use organization naming conventions
2. **Environment Separation** - Create separate projects for different environments
3. **Budget Monitoring** - Set up budget alerts for cost control
4. **Centralized Billing** - Use centralized billing buckets for organization-wide cost analysis
4. **API Management** - Only enable required APIs
5. **Folder Organization** - Use folders to organize projects logically
6. **Service Accounts** - Create dedicated service accounts for automation
7. **Labeling** - Use comprehensive labels for organization and billing

## Deployment Order

1. **Organization Setup** → Configure organization-level settings
2. **Folders** → Create organizational folders
3. **Projects** → Create projects within folders
4. **Project Resources** → Deploy resources within projects

## Troubleshooting

### Common Issues

1. **Billing Account Access**
   - Ensure the service account has `roles/billing.user`
   - Verify billing account exists and is active

2. **Folder Permission Errors**
   - Check `roles/resourcemanager.projectCreator` on folder
   - Verify folder ID is correct

3. **API Enablement Failures**
   - Ensure APIs exist and are available in the region
   - Check for organization policy restrictions

### Validation Commands

```bash
# List projects
gcloud projects list --filter="parent.id=FOLDER_ID"

# Check project APIs
gcloud services list --enabled --project=PROJECT_ID

# Verify billing association
gcloud beta billing projects describe PROJECT_ID
```

## Module Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `project_id` | ID of the created project | `"project-12345"` |
| `project_name` | Name of the project | `"Example Project"` |
| `project_number` | Numeric project identifier | `"123456789012"` |
| `service_account_email` | Project service account email | `"terraform-sa@project.iam.gserviceaccount.com"` |

## Security Considerations

1. **Service Account Management** - Use least privilege for service accounts
2. **API Security** - Only enable necessary APIs
3. **Budget Controls** - Set appropriate budget limits and alerts
4. **Access Controls** - Use IAM to control project access
5. **Audit Logging** - Enable audit logs for project changes

## References

- [terraform-google-project-factory module](https://github.com/terraform-google-modules/terraform-google-project-factory)
- [Google Cloud Project documentation](https://cloud.google.com/resource-manager/docs/creating-managing-projects)
- [Project Factory Best Practices](https://cloud.google.com/docs/enterprise/best-practices-for-enterprise-organizations)
- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/) 
