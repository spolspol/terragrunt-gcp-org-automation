# BigQuery Template

This document provides detailed information about the BigQuery template available in the Terragrunt GCP infrastructure.

## Overview

The BigQuery template (`_common/templates/bigquery.hcl`) provides a standardized approach to deploying Google Cloud BigQuery datasets and tables using the [terraform-google-bigquery](https://github.com/terraform-google-modules/terraform-google-bigquery) module. It ensures consistent configuration, environment-aware settings, and best practices for analytics workloads.

## Features

- Environment-aware dataset configuration (production vs. non-production)
- Standardized access controls for datasets
- Support for custom tables, views, and materialized views
- Schema templates for common use cases
- Labeling for resource management and cost allocation
- Deletion protection and content deletion controls

## Configuration Options

### Required Parameters

| Parameter      | Description                                 | Example                |
|---------------|---------------------------------------------|------------------------|
| `dataset_id`  | BigQuery dataset ID (must be unique)        | `analytics_dataset`    |
| `dataset_name` | Friendly name for the dataset               | `"Analytics Dataset"`  |
| `project_id`  | GCP project ID                              | `project-id`           |
| `location`    | GCP region for the dataset                  | `region`               |

### Optional Parameters with Defaults

| Parameter      | Default (non-prod)         | Default (prod)           | Description |
|----------------|---------------------------|--------------------------|-------------|
| `delete_contents_on_destroy` | `true`      | `false`                  | Delete tables on destroy |
| `deletion_protection`        | `false`     | `true`                   | Prevent accidental deletion |
| `access`       | See template              | See template             | Dataset access controls |
| `tables`       | `[]`                      | `[]`                     | List of tables to create |
| `views`        | `[]`                      | `[]`                     | List of views to create |
| `materialized_views` | `[]`                  | `[]`                     | List of materialized views |
| `dataset_labels` | See template             | See template             | Resource labels |

## Usage

### Basic Implementation

```hcl
include "bigquery_template" {
  path = "${get_parent_terragrunt_dir()}/_common/templates/bigquery.hcl"
}

dependency "project" {
  config_path = "../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

locals {
  merged_vars = merge(
    read_terragrunt_config(find_in_parent_folders("account.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("env.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("project.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals
  )
}

inputs = merge(
  read_terragrunt_config("${get_parent_terragrunt_dir()}/_common/templates/bigquery.hcl").inputs,
  {
    dataset_id   = replace("${local.merged_vars.name_prefix}_analytics_${local.merged_vars.environment}", "-", "_")
    dataset_name = "Analytics Dataset"
    project_id   = dependency.project.outputs.project_id
    location     = local.merged_vars.region
    
    tables = [
      {
        table_id = "example_table"
        schema   = "[]"
        labels   = { env = local.merged_vars.environment }
      }
    ]
    
    dataset_labels = merge(
      {
        component = "bigquery"
        environment = local.merged_vars.environment
      },
      local.merged_vars.org_labels,
      local.merged_vars.env_labels,
      local.merged_vars.project_labels
    )
  }
)
```

### Advanced Usage

#### Custom Tables with Schema

```hcl
inputs = merge(
  # ... other configuration ...
  {
    tables = [
      {
        table_id = "user_events"
        schema = jsonencode([
          {
            name = "timestamp"
            type = "TIMESTAMP"
            mode = "REQUIRED"
            description = "Event timestamp"
          },
          {
            name = "user_id"
            type = "STRING"
            mode = "REQUIRED"
            description = "User identifier"
          }
        ])
      }
    ]
  }
)
```

#### Views and Materialized Views

```hcl
inputs = merge(
  # ... other configuration ...
  {
    views = [
      {
        view_id = "user_summary"
        query   = "SELECT user_id, COUNT(*) as event_count FROM `${project_id}.${dataset_id}.user_events` GROUP BY user_id"
      }
    ]
    
    materialized_views = [
      {
        view_id = "daily_summary"
        query   = "SELECT DATE(timestamp) as date, COUNT(*) as events FROM `${project_id}.${dataset_id}.user_events` GROUP BY DATE(timestamp)"
      }
    ]
  }
)
```

## Best Practices

1. **Environment-Specific Settings** - Use environment-specific configurations for production vs. non-production
2. **Variable Names** - Use `dataset_name` for friendly names, not `friendly_name`
3. **Dataset ID Format** - Use underscores instead of hyphens in dataset IDs
4. **Labeling** - Use comprehensive labels for cost allocation and resource tracking
5. **Security** - Never hardcode sensitive data in configuration files
6. **Access Controls** - Use access blocks to control dataset permissions appropriately
7. **Template Usage** - Do not pass `environment_type` as it's not accepted by the BigQuery module

## Troubleshooting

### Common Issues

1. **Invalid dataset_id** - Ensure only letters, numbers, and underscores are used
2. **Schema errors** - Table schemas must be valid JSON arrays
3. **Permission errors** - Ensure the service account has `roles/bigquery.admin`
4. **API errors** - Ensure the BigQuery API is enabled for your project
5. **Unused input warnings** - Ensure you use `dataset_name` instead of `friendly_name` and don't pass `environment_type`

### Validation Commands

```bash
# List datasets
gcloud alpha bq datasets list --project=PROJECT_ID

# Describe a dataset
gcloud alpha bq datasets describe DATASET_ID --project=PROJECT_ID

# List tables in a dataset
gcloud alpha bq tables list --dataset=DATASET_ID --project=PROJECT_ID
```

## Module Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `dataset_id` | ID of the created dataset | `"analytics_dataset"` |
| `dataset_name` | Full name of the dataset | `"projects/project/datasets/analytics_dataset"` |
| `table_ids` | List of created table IDs | `["table1", "table2"]` |

## Implementation Examples

### Modular Dataset Organization

BigQuery datasets are organized in modular subdirectories for better management:

```
bigquery/
├── analytics-dataset/      # Analytics and event tracking data
├── audit-dataset/          # Audit logs and compliance tracking
├── reporting-dataset/      # Business reporting and dashboards
└── README.md              # Implementation guide
```

### Dataset Descriptions

#### analytics-dataset/
- **Purpose**: Analytics and event tracking data
- **Tables**: user_events, user_sessions
- **Use Case**: User behavior tracking, event analytics

#### audit-dataset/
- **Purpose**: Audit logs and compliance tracking
- **Tables**: system_audit_logs, user_access_logs
- **Use Case**: Security auditing, compliance reporting

#### reporting-dataset/
- **Purpose**: Business reporting and dashboards
- **Tables**: monthly_reports, daily_metrics
- **Views**: current_month_summary
- **Use Case**: Business intelligence, dashboard data

### Adding New Datasets

To add a new BigQuery dataset:

1. Create a new directory under `bigquery/` with a descriptive name
2. Copy the `terragrunt.hcl` template from an existing dataset
3. Customize the configuration:
   - Update `dataset_id`, `friendly_name`, and `description`
   - Define appropriate tables and their schemas
   - Set proper labels for organization
4. The workflows will automatically detect and include the new dataset

### Naming Convention

- Dataset IDs follow the pattern: `{name_prefix}_{dataset_folder_name}`
- Hyphens in folder names are converted to underscores for BigQuery compatibility
- Example: `analytics-dataset` → `tf_analytics_dataset`

### Workflow Integration

BigQuery datasets are managed by the Terragrunt workflows:
- **Validation Engine**: Validates configurations on pull requests
- **Deployment Engine**: Deploys changes on merge to main/develop

BigQuery datasets run in parallel with VPC networks, secrets, and storage buckets after project creation.

## References

- [terraform-google-bigquery module](https://github.com/terraform-google-modules/terraform-google-bigquery)
- [Google BigQuery documentation](https://cloud.google.com/bigquery/docs)
- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/) 
