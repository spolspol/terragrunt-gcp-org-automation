include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "folder_template" {
  path           = "${get_repo_root()}/_common/templates/folder.hcl"
  merge_strategy = "deep"
}

locals {
  # Folder-specific configuration - use parent directory name with optional prefix
  base_folder_name = basename(dirname(get_terragrunt_dir()))
  # Only use prefix if it exists and is not empty
  folder_name = include.base.locals.name_prefix != "" ? "${include.base.locals.name_prefix}-${local.base_folder_name}" : local.base_folder_name
}

inputs = {
  # Create a single folder for this environment
  names = [local.folder_name]

  # Parent is the organization ID from account vars
  parent = "organizations/${include.base.locals.merged.org_id}"

  # Prefix for folder names (optional - we're already including it in the name)
  prefix = ""

  # Set up folder admins who can create projects in this folder
  all_folder_admins = [
    "group:gg_org-devops@example.com",
    "serviceAccount:tofu-sa-org@org-automation.iam.gserviceaccount.com"
  ]

  # Define which roles the admins should have
  folder_admin_roles = [
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
    "roles/resourcemanager.folderViewer",
    "roles/billing.user",
    "roles/iam.serviceAccountUser",
    "roles/compute.admin",
    "roles/storage.admin",
    "roles/secretmanager.admin",
    "roles/networkconnectivity.hubAdmin" # Added for NCC hub management
  ]

  # Set roles on the created folders
  set_roles = true

  # Additional IAM bindings for specific permissions
  per_folder_admins = {
    "${local.folder_name}" = {
      members = [
        "serviceAccount:tofu-sa-org@org-automation.iam.gserviceaccount.com"
      ]
      roles = [] # Use default folder_admin_roles
    }
  }
}
