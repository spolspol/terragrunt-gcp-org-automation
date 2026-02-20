# IAM bindings for pki-hub project

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
    project_id = "org-pki-hub"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  org_service_member = "serviceAccount:tofu-sa-org@org-automation.iam.gserviceaccount.com"

  group_roles = {
    "group:ggg_env-hub-viewers@example.com" = [
      "roles/viewer",
    ]
    "group:ggg_env-hub-users@example.com" = [
      "roles/editor",
    ]
    "group:ggg_env-hub-admins@example.com" = [
      "roles/owner",
    ]
    "group:gg_org-devops@example.com" = [
      "roles/owner",
    ]
    # Security team for PKI management
    "group:gg_org-security@example.com" = [
      "roles/privateca.admin",
    ]
  }

  tofu_sa_org_bindings = {
    "roles/owner" = [local.org_service_member]
  }

  group_bindings = {
    for role in distinct(flatten(values(local.group_roles))) :
    role => sort(distinct([
      for group, roles in local.group_roles : group if contains(roles, role)
    ]))
  }

  bindings = {
    for role in distinct(concat(
      keys(local.group_bindings),
      keys(local.tofu_sa_org_bindings),
    )) :
    role => distinct(concat(
      lookup(local.group_bindings, role, []),
      lookup(local.tofu_sa_org_bindings, role, []),
    ))
  }
}

inputs = {
  projects = [dependency.project.outputs.project_id]
  mode     = "authoritative"
  bindings = local.bindings
}
