locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  # Dynamically assign project based on the top folder name
  project_name = basename(get_terragrunt_dir())
  project      = local.project_name
  project_id   = "pre-${local.project_name}-d"

  # Project-specific labels - only use prefix if it exists and is not empty
  name_prefix = try(local.env_vars.name_prefix, "")
  project_labels = {
    project     = local.name_prefix != "" ? "${local.name_prefix}-${local.project}" : local.project
    project_id  = local.name_prefix != "" ? "${local.name_prefix}-${local.project_id}" : local.project_id
    cost_center = "devops"
    purpose     = "infrastructure"
    application = "multi-purpose"
    team        = "platform"
  }

  # Project-specific service account
  project_service_account = local.name_prefix != "" ? "${local.name_prefix}-${local.project_id}-terraform@${local.name_prefix}-${local.project_id}.iam.gserviceaccount.com" : "${local.project_id}-terraform@${local.project_id}.iam.gserviceaccount.com"

  # Project-specific settings
  project_settings = {
  }

  # Default IAM bindings for project-level service account
  # These can be used if you have an IAM module in your Terragrunt config
  service_account_roles = [
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
    "roles/cloudsql.client"
  ]
}
