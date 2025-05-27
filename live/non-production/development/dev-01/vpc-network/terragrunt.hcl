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

include "network_template" {
  path = "${get_repo_root()}/_common/templates/network.hcl"
}

dependency "project" {
  config_path = "../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.common_vars.locals
  )

  # Only use prefix if it exists and is not empty
  name_prefix = try(local.merged_vars.name_prefix, "")
  # Use project_name from outputs for network naming (evaluated in inputs section)
  parent_folder_name = basename(get_terragrunt_dir())
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/network.hcl").inputs,
  local.merged_vars,
  {
    project_id       = try(dependency.project.outputs.project_id, "mock-project-id")
    network_name     = "${dependency.project.outputs.project_name}-${local.parent_folder_name}"
    environment_type = local.merged_vars.environment_type

    subnets = [
      {
        subnet_name           = "${dependency.project.outputs.project_name}-${local.parent_folder_name}-subnet-01"
        subnet_ip             = "10.10.0.0/16"
        subnet_region         = try(local.env_vars.locals.region, "europe-west2")
        subnet_private_access = true
        subnet_flow_logs      = false
        description           = "Primary subnet for ${dependency.project.outputs.project_name}-${local.parent_folder_name}"
      }
    ]

    # Optionally add secondary ranges, routes, firewall_rules, etc.
    network_labels = merge(
      {
        component   = "network"
        environment = local.merged_vars.environment
        name_prefix = local.name_prefix
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)
