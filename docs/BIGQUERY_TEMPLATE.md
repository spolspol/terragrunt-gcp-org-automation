# BigQuery Template

The BigQuery template (`_common/templates/bigquery.hcl`) creates datasets, tables, views, and materialized views using the [terraform-google-bigquery](https://github.com/terraform-google-modules/terraform-google-bigquery) module (v10.1.0). Datasets are deployed in parallel with VPC networks, secrets, and storage buckets after project creation.

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `dataset_id` | BigQuery dataset ID (unique, underscores only) | `analytics_dataset` |
| `dataset_name` | Friendly name for the dataset | `"Analytics Dataset"` |
| `project_id` | GCP project ID | `"project-id"` |
| `location` | GCP region | `"europe-west2"` |

### Optional Parameters

| Parameter | Default (non-prod) | Default (prod) | Description |
|-----------|-------------------|----------------|-------------|
| `delete_contents_on_destroy` | `true` | `false` | Delete tables on destroy |
| `deletion_protection` | `false` | `true` | Prevent accidental deletion |
| `access` | See template | See template | Dataset access controls |
| `tables` | `[]` | `[]` | List of tables to create |
| `views` | `[]` | `[]` | List of views to create |
| `materialized_views` | `[]` | `[]` | List of materialized views |
| `dataset_labels` | See template | See template | Resource labels |

## Directory Structure

```
live/non-production/development/platform/dp-dev-01/
└── europe-west2/
    └── bigquery/
        └── landing-example/       # Example analytics dataset
            └── terragrunt.hcl
```

## Usage

### Basic Implementation

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "bigquery_template" {
  path           = "${get_repo_root()}/_common/templates/bigquery.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  dataset_id   = replace("${include.base.locals.merged.name_prefix}_analytics_${include.base.locals.environment}", "-", "_")
  dataset_name = "Analytics Dataset"
  project_id   = dependency.project.outputs.project_id
  location     = include.base.locals.region

  tables = [
    {
      table_id = "example_table"
      schema   = "[]"
      labels   = { env = include.base.locals.environment }
    }
  ]

  dataset_labels = merge(
    {
      component   = "bigquery"
      environment = include.base.locals.environment
    },
    include.base.locals.standard_labels
  )
}
```

### Custom Tables with Schema

```hcl
inputs = {
  tables = [
    {
      table_id = "user_events"
      schema = jsonencode([
        { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED", description = "Event timestamp" },
        { name = "user_id",   type = "STRING",    mode = "REQUIRED", description = "User identifier" }
      ])
    }
  ]
}
```

### Views and Materialized Views

```hcl
inputs = {
  views = [
    {
      view_id = "user_summary"
      query   = "SELECT user_id, COUNT(*) as event_count FROM `project.dataset.user_events` GROUP BY user_id"
    }
  ]
  materialized_views = [
    {
      view_id = "daily_summary"
      query   = "SELECT DATE(timestamp) as date, COUNT(*) as events FROM `project.dataset.user_events` GROUP BY DATE(timestamp)"
    }
  ]
}
```

## Adding New Datasets

1. Create a directory under `bigquery/` with a descriptive name
2. Copy `terragrunt.hcl` from an existing dataset
3. Update `dataset_id`, `dataset_name`, and table schemas
4. Dataset IDs convert hyphens to underscores automatically (e.g. `analytics-dataset` becomes `tf_analytics_dataset`)

## Best Practices

- Use `dataset_name` (not `friendly_name`) for compatibility with v10.1.0+
- Use underscores in dataset IDs -- hyphens are invalid in BigQuery
- Do not pass `environment_type` as the BigQuery module does not accept it
- Enable `deletion_protection` in production environments
- Apply access blocks rather than legacy `authorized_views`

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Invalid `dataset_id` | Use only letters, numbers, and underscores |
| Schema errors | Table schemas must be valid JSON arrays |
| Permission errors | Ensure `roles/bigquery.admin` on the service account |
| Unused input warnings | Verify you use `dataset_name` and do not pass `environment_type` |

```bash
gcloud alpha bq datasets list --project=PROJECT_ID
gcloud alpha bq datasets describe DATASET_ID --project=PROJECT_ID
gcloud alpha bq tables list --dataset=DATASET_ID --project=PROJECT_ID
```

## Module Outputs

| Output | Description |
|--------|-------------|
| `dataset_id` | ID of the created dataset |
| `dataset_name` | Full name of the dataset |
| `table_ids` | List of created table IDs |

## References

- [terraform-google-bigquery module](https://github.com/terraform-google-modules/terraform-google-bigquery)
- [Google BigQuery documentation](https://cloud.google.com/bigquery/docs)
