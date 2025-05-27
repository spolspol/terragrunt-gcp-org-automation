include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "folder_template" {
  path = "${get_repo_root()}/_common/templates/folder.hcl"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.common_vars.locals
  )

  # Folder-specific configuration - use parent directory name with optional prefix
  base_folder_name = basename(dirname(get_terragrunt_dir()))
  # Only use prefix if it exists and is not empty
  name_prefix = try(local.merged_vars.name_prefix, "")
  folder_name = local.name_prefix != "" ? "${local.name_prefix}-${local.base_folder_name}" : local.base_folder_name
}

inputs = {
  # Create a single folder for this environment
  names = [local.folder_name]

  # Parent is the organization ID from account vars
  parent = "organizations/${local.merged_vars.org_id}"

  # Prefix for folder names (optional - we're already including it in the name)
  prefix = ""

  # Set up folder admins who can create projects in this folder.
  all_folder_admins = [
    "group:gcp-devops@example.com",                           # Replace with your actual admin group
    "serviceAccount:tofu-sa-org@org-automation.iam.gserviceaccount.com" # Service account for automation
  ]

  # Define which roles the admins should have
  folder_admin_roles = [
    "roles/resourcemanager.folderAdmin",    # Manage folders
    "roles/resourcemanager.projectCreator", # Create projects in folder
    "roles/resourcemanager.folderViewer",   # View folder structure
    "roles/billing.user",                   # Link billing accounts to projects
    "roles/iam.serviceAccountUser",         # Use service accounts
    "roles/compute.admin",                  # Manage compute resources
    "roles/storage.admin",                  # Manage storage resources
    "roles/secretmanager.admin",            # Manage secrets
    "roles/bigquery.admin",                 # Manage BigQuery resources
    "roles/cloudsql.admin"                  # Manage Cloud SQL resources
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
