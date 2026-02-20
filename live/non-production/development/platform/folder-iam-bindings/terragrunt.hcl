# Folder IAM bindings for Platform sub-environment

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
      "platform" = "folders/123456789012345"
    }
    id = "folders/123456789012345"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  org_service_member = "serviceAccount:${include.base.locals.merged.org_service_account}"

  group_roles = {
    "group:ggg_env-development-viewers@example.com" = [
      "roles/resourcemanager.folderViewer",
    ]
    "group:gg_org-devops@example.com" = [
      "roles/resourcemanager.folderEditor",
    ]
    "group:gg_org-security@example.com" = [
      "roles/resourcemanager.folderAdmin",
    ]
  }

  group_bindings = {
    for role in distinct(flatten(values(local.group_roles))) :
    role => sort(distinct([
      for group, roles in local.group_roles : group if contains(roles, role)
    ]))
  }

  sa_bindings = {
    "roles/resourcemanager.folderAdmin"  = [local.org_service_member]
    "roles/resourcemanager.folderViewer" = [local.org_service_member]
  }

  all_bindings = {
    for role in distinct(concat(
      keys(local.group_bindings),
      keys(local.sa_bindings),
    )) :
    role => distinct(concat(
      lookup(local.group_bindings, role, []),
      lookup(local.sa_bindings, role, []),
    ))
  }
}

inputs = {
  folders  = [dependency.folder.outputs.ids["platform"]]
  mode     = "additive"
  bindings = local.all_bindings
}
