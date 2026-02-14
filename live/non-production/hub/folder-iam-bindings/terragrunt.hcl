# IAM bindings for hub folder

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "folder_iam_template" {
  path           = "${get_repo_root()}/_common/templates/folder_iam_bindings.hcl"
  merge_strategy = "deep"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    ids = {
      "hub" = "folders/123456789012"
    }
    names = ["hub"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  # Folder-specific configuration - mirror folder module naming
  base_folder_name = basename(dirname(get_terragrunt_dir()))
  folder_name      = include.base.locals.name_prefix != "" ? "${include.base.locals.name_prefix}-${local.base_folder_name}" : local.base_folder_name

  # ============================================================================
  # 1. GROUP ROLES (Group -> [roles])
  # ============================================================================

  group_roles = {
    # Hub viewers
    "group:ggg_env-hub-viewers@example.com" = [
      "roles/resourcemanager.folderViewer",
    ]
    # Network admins
    "group:gg_org-vpc-network-admins@example.com" = [
      "roles/resourcemanager.folderViewer",
    ]
    # DevOps team
    "group:gg_org-devops@example.com" = [
      "roles/resourcemanager.folderAdmin",
    ]
    # Security team
    "group:gg_org-security@example.com" = [
      "roles/resourcemanager.folderAdmin",
    ]
  }

  # ============================================================================
  # 2. TRANSFORMS
  # ============================================================================

  # Transform group_roles to group_bindings (Role -> [groups])
  group_bindings = {
    for role in distinct(flatten(values(local.group_roles))) :
    role => sort(distinct([
      for group, roles in local.group_roles : group if contains(roles, role)
    ]))
  }

  # ============================================================================
  # 3. FINAL BINDINGS
  # ============================================================================

  bindings = local.group_bindings
}

inputs = {
  folders = [
    startswith(tostring(dependency.folder.outputs.ids[local.folder_name]), "folders/")
    ? tostring(dependency.folder.outputs.ids[local.folder_name])
    : "folders/${tostring(dependency.folder.outputs.ids[local.folder_name])}"
  ]
  mode     = "authoritative"
  bindings = local.bindings
}
