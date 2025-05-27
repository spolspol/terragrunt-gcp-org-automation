# IAM Bindings Template
# This template provides standardized IAM binding management for GCP projects
# Include this template in your Terragrunt configurations for consistent IAM setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-iam.git//modules/projects_iam?ref=${local.module_versions.iam}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Default IAM configuration
  default_iam_config = {
    mode = "additive" # Default to additive mode to avoid accidentally removing existing bindings
  }

  # Common role bindings for service accounts
  common_service_account_roles = {
    basic = [
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter"
    ]
    compute = [
      "roles/compute.instanceAdmin",
      "roles/storage.objectAdmin",
      "roles/secretmanager.secretAccessor"
    ]
    storage = [
      "roles/storage.admin",
      "roles/storage.objectAdmin"
    ]
    secrets = [
      "roles/secretmanager.secretAccessor",
      "roles/secretmanager.viewer"
    ]
  }
}

# Default inputs - can be overridden in the child module
inputs = {
  mode = local.default_iam_config.mode
}
