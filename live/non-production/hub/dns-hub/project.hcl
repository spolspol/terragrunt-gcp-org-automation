locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  # Dynamically assign project based on the top folder name
  project_name = basename(get_terragrunt_dir())
  project      = local.project_name
  project_id   = local.name_prefix != "" ? "${local.name_prefix}-${local.project}" : "org-${local.project}"

  # Project-specific labels
  name_prefix = try(local.env_vars.name_prefix, "")
  project_labels = {
    project     = local.project
    project_id  = local.project_id
    cost_center = "infrastructure"
    purpose     = "global-dns-management"
    environment = "hub"
  }

  # Project service account
  project_service_account = local.name_prefix != "" ? "${local.name_prefix}-${local.project_id}-terraform@${local.name_prefix}-${local.project_id}.iam.gserviceaccount.com" : "${local.project_id}-terraform@${local.project_id}.iam.gserviceaccount.com"

  # DNS-specific service APIs
  activate_apis = [
    "dns.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "compute.googleapis.com" # For VPC if private zones are added later
  ]

  # Service account roles for DNS management
  service_account_roles = [
    "roles/dns.admin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]

  # Project-specific settings
  project_settings = {
    dns_zones_count_limit = 100 # Default GCP limit
    enable_dnssec         = true
  }
}
