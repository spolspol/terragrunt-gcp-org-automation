# Project Factory Template
# This template provides standardized GCP project creation and configuration
# Include this template in your Terragrunt configurations for consistent project setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-project-factory.git//?ref=${local.module_versions.project_factory}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default project configuration
  default_project_config = {
    auto_create_network         = false
    default_service_account     = "keep"
    disable_services_on_destroy = false
    lien                        = false

    # Default APIs to activate - essential services
    default_activate_apis = [
    ]
  }

  # Default project roles for project-level service accounts
  default_project_sa_roles = [
    "roles/compute.admin",
    "roles/storage.admin",
    "roles/secretmanager.admin",
    "roles/bigquery.admin",
    "roles/cloudsql.admin"
  ]
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  name            = null # Project name - must be provided
  project_id      = null # Project ID - must be provided
  org_id          = null # Organization ID - must be provided
  billing_account = null # Billing account - must be provided

  # Folder configuration - optional
  folder_id = null

  # Network configuration
  auto_create_network = local.default_project_config.auto_create_network

  # Service account configuration
  default_service_account = local.default_project_config.default_service_account

  # API activation - merge default and environment-specific APIs
  activate_apis = local.default_project_config.default_activate_apis

  # Disable services on destroy based on environment
  disable_services_on_destroy = local.default_project_config.disable_services_on_destroy

  # Lien configuration based on environment
  lien = local.default_project_config.lien

  # Default project labels
  labels = {
    managed_by = "terragrunt"
    component  = "project"
  }

  # Budget configuration - optional, can be overridden
  budget_amount           = null
  budget_alert_thresholds = [0.5, 0.75, 0.9, 1.0]

  # Shared VPC configuration - optional
  # shared_vpc         = null
  # shared_vpc_subnets = []

  # Essential contacts configuration - optional
  essential_contacts = {}

  # Usage bucket configuration - optional
  usage_bucket_name   = null
  usage_bucket_prefix = null

  # Enable specific services based on environment needs
  enable_shared_vpc_host_project    = false
  enable_shared_vpc_service_project = false

  # Grant service account roles to the default compute service account
  grant_network_role = true

  # Tags for organization policy compliance - required for project creation
  tag_binding_values = []
}
