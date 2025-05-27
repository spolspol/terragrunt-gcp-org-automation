# Cloud Storage Bucket Template
# This template provides standardized GCS bucket configuration
# Include this template in your Terragrunt configurations for consistent bucket setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-cloud-storage.git//?ref=${local.module_versions.cloud_storage}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default environment type (will be overridden by bucket configurations)
  environment_type = "non-production"

  # Default bucket configuration
  default_bucket_config = {
    location                    = "europe-west2"
    storage_class               = "STANDARD"
    versioning_enabled          = true
    lifecycle_rules             = []
    iam_members                 = []
    bucket_policy_only          = true
    uniform_bucket_level_access = true
    public_access_prevention    = "enforced"
    force_destroy               = false
    encryption                  = {}
    retention_policy            = {}
    logging                     = {}
    website                     = {}
    cors                        = []
    custom_placement_config     = {}
  }

  # Environment-specific settings
  env_bucket_configs = {
    production = {
      versioning_enabled          = true
      force_destroy               = false
      public_access_prevention    = "enforced"
      uniform_bucket_level_access = true
      storage_class               = "STANDARD"
    }
    non-production = {
      versioning_enabled          = true
      force_destroy               = true
      public_access_prevention    = "enforced"
      uniform_bucket_level_access = true
      storage_class               = "STANDARD"
    }
  }

  # Standard lifecycle rules for different bucket types
  standard_lifecycle_rules = {
    log_bucket = [
      {
        action = {
          type = "Delete"
        }
        condition = {
          age = 90
        }
      },
      {
        action = {
          type          = "SetStorageClass"
          storage_class = "COLDLINE"
        }
        condition = {
          age = 30
        }
      }
    ]
    backup_bucket = [
      {
        action = {
          type          = "SetStorageClass"
          storage_class = "NEARLINE"
        }
        condition = {
          age = 30
        }
      },
      {
        action = {
          type          = "SetStorageClass"
          storage_class = "COLDLINE"
        }
        condition = {
          age = 90
        }
      },
      {
        action = {
          type          = "SetStorageClass"
          storage_class = "ARCHIVE"
        }
        condition = {
          age = 365
        }
      }
    ]
    temp_bucket = [
      {
        action = {
          type = "Delete"
        }
        condition = {
          age = 7
        }
      }
    ]
  }
}

# Example usage:
#
# locals {
#   name_prefix = local.merged_vars.name_prefix != "" ? local.merged_vars.name_prefix : "tg"
#   # Use parent folder name (buckets) for bucket naming with name_prefix-project_name prefix
#   parent_folder_name = basename(dirname(get_terragrunt_dir()))
#   bucket_name        = "${local.name_prefix}-${local.merged_vars.project_name}-${local.parent_folder_name}"
# }
#
# include "bucket_template" {
#   path = "${get_parent_terragrunt_dir()}/_common/templates/cloud_storage.hcl"
# }
#
# inputs = merge(
#   read_terragrunt_config("${get_parent_terragrunt_dir()}/_common/templates/cloud_storage.hcl").inputs,
#   {
#     project_id = local.project_id
#     names      = [local.bucket_name]  # Uses name_prefix-project_name-parent_folder_name
#
#     # Optional: Override the template defaults for module v11.0.0+ with explicit maps
#     # versioning = {
#     #   (lower(local.bucket_name)) = true
#     # }
#     # bucket_policy_only = {
#     #   (lower(local.bucket_name)) = true
#     # }
#     # force_destroy = {
#     #   (lower(local.bucket_name)) = false
#     # }
#
#     lifecycle_rules = [
#       {
#         action = {
#           type = "Delete"
#         }
#         condition = {
#           age = 30
#         }
#       }
#     ]
#
#     labels = merge(
#       local.org_labels,
#       local.env_labels,
#       local.project_labels,
#       {
#         component = "storage"
#         purpose   = "data-processing"
#       }
#     )
#   }
# )

# Default inputs - these will be merged with specific configurations
# Note: template-internal variables (environment_type, bucket_type) are excluded from final module inputs
inputs = {
  # Required parameters - must be provided in specific implementations
  project_id = null # Must be provided
  names      = []   # List of bucket names - must be provided

  # Optional prefix for bucket names
  prefix = ""

  # Location and storage configuration
  location      = local.default_bucket_config.location
  storage_class = local.default_bucket_config.storage_class

  # Environment-specific versioning - convert to map format for v11.0.0
  versioning = {}

  # Environment-specific force destroy - convert to map format for v11.0.0
  force_destroy = {}

  # Security settings - convert to map format for v11.0.0
  bucket_policy_only          = {}
  uniform_bucket_level_access = local.default_bucket_config.uniform_bucket_level_access
  public_access_prevention    = local.default_bucket_config.public_access_prevention

  # Optional lifecycle rules - can use predefined templates
  lifecycle_rules = local.default_bucket_config.lifecycle_rules

  # Convert iam_members to module's expected format
  admins = []

  creators = []

  # Optional encryption configuration
  encryption = local.default_bucket_config.encryption

  # Optional retention policy
  retention_policy = local.default_bucket_config.retention_policy

  # Optional logging configuration
  logging = local.default_bucket_config.logging

  # Optional website configuration
  website = local.default_bucket_config.website

  # Optional CORS configuration
  cors = local.default_bucket_config.cors

  # Optional custom placement configuration
  custom_placement_config = local.default_bucket_config.custom_placement_config

  # Labels
  labels = {
    managed_by = "terragrunt"
    component  = "storage"
  }

  # Randomize suffix for bucket names
  randomize_suffix = false

  # Set default to true for folder-per-bucket mode
  set_admin_roles   = true
  set_creator_roles = true
  set_viewer_roles  = true
}
