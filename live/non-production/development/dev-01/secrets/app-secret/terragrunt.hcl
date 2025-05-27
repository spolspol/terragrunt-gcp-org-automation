include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "project" {
  path = find_in_parent_folders("project.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "secret_template" {
  path = "${get_repo_root()}/_common/templates/secret_manager.hcl"
}

include "secrets_common" {
  path = find_in_parent_folders("secrets.hcl")
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
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  secrets_vars = read_terragrunt_config(find_in_parent_folders("secrets.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.secrets_vars.locals,
    local.common_vars.locals
  )

  # Only use prefix if it exists and is not empty
  name_prefix         = try(local.merged_vars.name_prefix, "")
  selected_env_config = lookup(local.merged_vars.environment_secret_settings, local.merged_vars.environment_type, {})

  # Secret-specific configuration
  secret_name = basename(get_terragrunt_dir())

  # Evaluate environment variable at Terragrunt level
  secret_value = get_env("EXAMPLE_SECRET_VALUE", "")
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/secret_manager.hcl").inputs,
  local.merged_vars,
  local.selected_env_config,
  {
    project_id            = try(dependency.project.outputs.project_id, "mock-project-id")
    automatic_replication = {}
    secrets = [
      {
        name           = local.secret_name
        secret_data    = local.secret_value != "" ? local.secret_value : null
        create_version = local.secret_value != "" ? true : false
        # Optionally: rotation_period, etc.
      }
    ]
    secret_accessors_list = [
      "serviceAccount:${try(dependency.project.outputs.service_account_email, "mock-sa@mock-project-id.iam.gserviceaccount.com")}"
    ]
    labels = {
      "${local.secret_name}" = merge(
        local.merged_vars.common_secret_labels,
        {
          secret_type      = "application"
          purpose          = "example"
          environment      = local.merged_vars.environment
          environment_type = local.merged_vars.environment_type
          name_prefix      = local.name_prefix
        },
        try(local.merged_vars.org_labels, {}),
        try(local.merged_vars.env_labels, {}),
        try(local.merged_vars.project_labels, {})
      )
    }
  }
)
