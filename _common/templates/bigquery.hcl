# BigQuery Module Template
# This template provides standardized BigQuery dataset and table configurations
# Include this template in your Terragrunt configurations for consistent BigQuery setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-bigquery.git//?ref=${local.module_versions.bigquery}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default dataset configuration
  default_dataset_config = {
    delete_contents_on_destroy = false
    deletion_protection        = true
    # Default access
    access = [
      {
        role          = "OWNER"
        special_group = "projectOwners"
      },
      {
        role          = "READER"
        special_group = "projectReaders"
      },
      {
        role          = "WRITER"
        special_group = "projectWriters"
      }
    ]
  }

  # Environment-specific settings
  env_dataset_configs = {
    production = {
      delete_contents_on_destroy = false
      deletion_protection        = true
    }
    non-production = {
      delete_contents_on_destroy = true
      deletion_protection        = false
    }
  }

  # Schema template examples for common table types
  schema_templates = {
    audit_log = {
      fields = [
        {
          name        = "timestamp",
          type        = "TIMESTAMP",
          mode        = "REQUIRED",
          description = "When the event occurred"
        },
        {
          name        = "actor",
          type        = "STRING",
          mode        = "REQUIRED",
          description = "Who performed the action"
        },
        {
          name        = "action",
          type        = "STRING",
          mode        = "REQUIRED",
          description = "What action was performed"
        },
        {
          name        = "resource",
          type        = "STRING",
          mode        = "REQUIRED",
          description = "Resource that was affected"
        },
        {
          name        = "details",
          type        = "JSON",
          mode        = "NULLABLE",
          description = "Additional event details"
        }
      ]
    },
    metrics = {
      fields = [
        {
          name        = "timestamp",
          type        = "TIMESTAMP",
          mode        = "REQUIRED",
          description = "When the metric was recorded"
        },
        {
          name        = "metric_name",
          type        = "STRING",
          mode        = "REQUIRED",
          description = "Name of the metric"
        },
        {
          name        = "metric_value",
          type        = "FLOAT",
          mode        = "REQUIRED",
          description = "Value of the metric"
        },
        {
          name        = "dimensions",
          type        = "JSON",
          mode        = "NULLABLE",
          description = "Additional dimensions for the metric"
        }
      ]
    }
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  dataset_id   = try(inputs.dataset_id, "example_dataset")
  dataset_name = try(inputs.dataset_name, "Example Dataset")
  description  = try(inputs.description, "Dataset created via Terragrunt")

  # Merge environment-specific configuration based on the environment_type local
  delete_contents_on_destroy = lookup(
    local.env_dataset_configs[try(inputs.environment_type, "non-production")],
    "delete_contents_on_destroy",
    local.default_dataset_config.delete_contents_on_destroy
  )

  deletion_protection = lookup(
    local.env_dataset_configs[try(inputs.environment_type, "non-production")],
    "deletion_protection",
    local.default_dataset_config.deletion_protection
  )

  # Default access configuration
  access = local.default_dataset_config.access

  # Default table configurations - override in specific implementations
  tables = try(inputs.tables, [])

  # Default views - override in specific implementations
  views = try(inputs.views, [])

  # Default materialized views - override in specific implementations
  materialized_views = try(inputs.materialized_views, [])

  # Default dataset labels
  dataset_labels = try(inputs.dataset_labels, {
    managed_by = "terragrunt"
    component  = "bigquery"
  })
}
