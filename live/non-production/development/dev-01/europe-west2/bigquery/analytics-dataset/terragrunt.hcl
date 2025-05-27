include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "project" {
  path = find_in_parent_folders("project.hcl")
}

include "region" {
  path = find_in_parent_folders("region.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "bigquery_template" {
  path = "${get_repo_root()}/_common/templates/bigquery.hcl"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )

  # Use project-based naming following <project_name>-<parent_folder_name> pattern
  # BigQuery dataset IDs use underscores instead of dashes
  dataset_folder_name = basename(get_terragrunt_dir())
}

# Dependency on the project module
dependency "project" {
  config_path = "../../../project"

  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/bigquery.hcl").inputs,
  {
    # Dataset configuration - use <project_name>-<parent_folder_name> pattern
    dataset_id   = replace("${try(dependency.project.outputs.project_name, "mock-project-name")}-${local.dataset_folder_name}", "-", "_")
    dataset_name = "Analytics Dataset"
    description  = "BigQuery dataset for analytics data and reporting"
    project_id   = try(dependency.project.outputs.project_id, local.merged_vars.project)
    location     = local.merged_vars.region

    # Analytics-specific tables
    tables = [
      {
        table_id = "user_events"
        schema = jsonencode([
          {
            name        = "event_timestamp",
            type        = "TIMESTAMP",
            mode        = "REQUIRED",
            description = "When the event occurred"
          },
          {
            name        = "user_id",
            type        = "STRING",
            mode        = "REQUIRED",
            description = "User identifier"
          },
          {
            name        = "event_type",
            type        = "STRING",
            mode        = "REQUIRED",
            description = "Type of event"
          },
          {
            name        = "event_properties",
            type        = "JSON",
            mode        = "NULLABLE",
            description = "Additional event properties"
          }
        ])
        labels = {
          env       = local.merged_vars.environment_type,
          data_type = "analytics",
          purpose   = "events"
        }
      },
      {
        table_id = "user_sessions"
        schema = jsonencode([
          {
            name        = "session_id",
            type        = "STRING",
            mode        = "REQUIRED",
            description = "Unique session identifier"
          },
          {
            name        = "user_id",
            type        = "STRING",
            mode        = "REQUIRED",
            description = "User identifier"
          },
          {
            name        = "session_start",
            type        = "TIMESTAMP",
            mode        = "REQUIRED",
            description = "Session start time"
          },
          {
            name        = "session_end",
            type        = "TIMESTAMP",
            mode        = "NULLABLE",
            description = "Session end time"
          },
          {
            name        = "page_views",
            type        = "INTEGER",
            mode        = "NULLABLE",
            description = "Number of page views in session"
          }
        ])
        labels = {
          env       = local.merged_vars.environment_type,
          data_type = "analytics",
          purpose   = "sessions"
        }
      }
    ]

    # Environment-specific labels
    dataset_labels = merge(
      {
        component        = "bigquery"
        environment      = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
        purpose          = "analytics"
        dataset_type     = "analytics"
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)
