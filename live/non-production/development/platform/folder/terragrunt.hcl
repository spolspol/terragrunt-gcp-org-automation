# Platform sub-environment folder

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

dependency "parent_folder" {
  config_path = "../../folder"
  mock_outputs = {
    ids = {
      "development" = "folders/123456789012345"
    }
    id = "folders/123456789012345"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  folder_name = "platform"
}

inputs = {
  names  = [local.folder_name]
  parent = dependency.parent_folder.outputs.ids[include.base.locals.merged.environment_name]
  prefix = ""

  all_folder_admins = [
    "group:gg_org-devops@example.com",
    "serviceAccount:tofu-sa-org@org-automation.iam.gserviceaccount.com"
  ]

  folder_admin_roles = [
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
    "roles/resourcemanager.folderViewer",
    "roles/billing.user",
    "roles/iam.serviceAccountUser",
    "roles/compute.admin",
    "roles/storage.admin",
    "roles/secretmanager.admin",
    "roles/bigquery.admin",
    "roles/cloudsql.admin",
    "roles/container.admin",
  ]

  set_roles = true

  per_folder_admins = {
    "${local.folder_name}" = {
      members = [
        "serviceAccount:tofu-sa-org@org-automation.iam.gserviceaccount.com"
      ]
      roles = []
    }
  }
}
