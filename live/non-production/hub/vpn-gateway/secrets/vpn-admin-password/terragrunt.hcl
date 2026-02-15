include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "secrets_common" {
  path   = find_in_parent_folders("secrets.hcl")
  expose = true
}

include "secret_template" {
  path           = "${get_repo_root()}/_common/templates/secret_manager.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id            = "mock-project-id"
    service_account_email = "mock-sa@mock-project-id.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  # Secret-specific configuration
  secret_name = include.base.locals.resource_name

  # Evaluate environment variable at Terragrunt level
  secret_value = get_env("VPN_ADMIN_PASSWORD", "")
}

inputs = {
  project_id            = try(dependency.project.outputs.project_id, "mock-project-id")
  automatic_replication = {}

  secrets = [
    {
      name           = local.secret_name
      secret_data    = local.secret_value != "" ? local.secret_value : null
      create_version = local.secret_value != "" ? true : false
    }
  ]

  secret_accessors_list = [
    "serviceAccount:${try(dependency.project.outputs.service_account_email, "mock-sa@mock-project-id.iam.gserviceaccount.com")}"
  ]

  labels = {
    "${local.secret_name}" = merge(
      include.secrets_common.locals.common_secret_labels,
      {
        secret_type = "password"
        purpose     = "vpn-admin"
        environment = include.base.locals.environment
        instance    = "vpn-server"
      }
    )
  }
}
