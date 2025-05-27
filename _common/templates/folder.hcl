# Folder Template
# This template provides standardized GCP folder creation and configuration
# Include this template in your Terragrunt configurations for consistent folder setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-folders.git//?ref=${local.module_versions.folders}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default folder configuration
  default_folder_config = {
    # Parent can be organization or another folder
    parent_type = "organization" # or "folder"

    # Default folder settings
    auto_create_network = false
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  names  = []   # List of folder names - must be provided
  parent = null # Parent organization or folder ID - must be provided

  # Optional parameters with defaults

  # Prefix for all folder names
  prefix = ""

  # Whether to create the folders sequentially (second depends on first, etc)
  # Set to true for hierarchical folder structures
  set_roles = false

  ###############
  # Deletion protection for folders (prevents accidental deletion)
  # Set to false to allow destroy; set to true for safety in production
  deletion_protection = false
  ###############

  # IAM roles for folders - will be applied to all folders created
  # Format: { "roles/role_name" = ["member1", "member2"] }
  per_folder_admins = {}

  # All folders will have the same admins
  all_folder_admins = []

  # Folder-specific admins
  # Format: { "folder_name" = ["member1", "member2"] }
  folder_admin_roles = [
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator"
  ]
}
