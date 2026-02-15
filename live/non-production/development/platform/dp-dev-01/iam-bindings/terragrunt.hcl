# Project-level IAM bindings for dp-dev-01

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "iam_template" {
  path           = "${get_repo_root()}/_common/templates/iam_bindings.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../project"
  mock_outputs = {
    project_id            = "mock-project-id"
    service_account_email = "mock-sa@mock-project-id.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  org_service_member = "serviceAccount:${include.base.locals.merged.org_service_account}"
  default_sa_member  = "serviceAccount:${dependency.project.outputs.project_id}@appspot.gserviceaccount.com"

  group_roles = {
    "group:ggg_env-development-viewers@example.com" = [
      "roles/viewer",
    ]
    "group:ggg_env-development-users@example.com" = [
      "roles/container.viewer",
      "roles/bigquery.dataViewer",
      "roles/logging.viewer",
    ]
    "group:ggg_env-development-admins@example.com" = [
      "roles/editor",
    ]
  }

  sa_roles = {
    "roles/owner"                       = [local.org_service_member]
    "roles/logging.logWriter"           = [local.default_sa_member]
    "roles/monitoring.metricWriter"     = [local.default_sa_member]
  }

  group_bindings = {
    for role in distinct(flatten(values(local.group_roles))) :
    role => sort(distinct([
      for group, roles in local.group_roles : group if contains(roles, role)
    ]))
  }

  all_bindings = {
    for role in distinct(concat(
      keys(local.group_bindings),
      keys(local.sa_roles),
    )) :
    role => distinct(concat(
      lookup(local.group_bindings, role, []),
      lookup(local.sa_roles, role, []),
    ))
  }
}

inputs = {
  projects = [dependency.project.outputs.project_id]
  mode     = "authoritative"
  bindings = local.all_bindings
}
