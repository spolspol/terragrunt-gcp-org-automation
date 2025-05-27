# Secret Manager Template
# This template provides a standardized approach for managing individual secrets in GCP Secret Manager
# Include this template in your Terragrunt configurations for consistent secret management

terraform {
  source = "git::https://github.com/GoogleCloudPlatform/terraform-google-secret-manager.git//?ref=${local.module_versions.secret_manager}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default access roles for secret manager
  default_secret_roles = [
    "roles/secretmanager.secretAccessor",
    "roles/secretmanager.viewer"
  ]

  # Standard secret configuration
  default_secret_settings = {
    automatic_replication = {}
    rotation_period       = "7776000s" # 90 days
  }

  # Environment-specific settings
  env_secret_configs = {
    production = {
      deletion_protection = true
      rotation_enabled    = true
    }
    non-production = {
      deletion_protection = false
      rotation_enabled    = false
    }
  }
}

# Example usage:
#
# include "secret_template" {
#   path = "${get_parent_terragrunt_dir()}/_common/templates/secret_manager.hcl"
# }
#
# inputs = merge(
#   read_terragrunt_config("${get_parent_terragrunt_dir()}/_common/templates/secret_manager.hcl").inputs,
#   {
#     project_id = local.project_id
#     secrets = [
#       {
#         name                  = "my-secret-name"
#         secret_data           = get_env("MY_SECRET_VALUE", "")
#         automatic_replication = {}
#       }
#     ]
#
#     labels = merge(
#       local.org_labels,
#       local.env_labels,
#       local.project_labels,
#       {
#         component = "secret-manager"
#       }
#     )
#
#     # IAM bindings for each secret
#     secret_accessors_list = [
#       "serviceAccount:${local.project_service_account}"
#     ]
#   }
# )

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required project_id - must be provided in specific implementations
  project_id = null

  # Standard secret rotation and replication settings
  automatic_replication = local.default_secret_settings.automatic_replication

  # Default empty secrets list - will be overridden in specific implementations
  secrets = []

  # Default empty labels - will be merged with specific labels
  labels = {}

  # Default empty accessors list - will be overridden in specific implementations
  secret_accessors_list = []

  # Optional KMS and PubSub permissions
  add_kms_permissions    = []
  add_pubsub_permissions = []

  # Optional topics for rotation notifications
  topics = {}

  # Optional user-managed replication
  user_managed_replication = {}
}
