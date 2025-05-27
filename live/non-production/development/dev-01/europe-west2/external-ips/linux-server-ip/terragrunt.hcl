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

include "region" {
  path = find_in_parent_folders("region.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "external_ip_template" {
  path = "${get_repo_root()}/_common/templates/external_ip.hcl"
}

# Dependency on the VPC network module
dependency "network" {
  config_path = "../../../vpc-network"

  mock_outputs = {
    network_name      = "mock-network"
    network_self_link = "projects/mock-project/global/networks/mock-network"
    project_id        = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

# Dependency on the project module
dependency "project" {
  config_path = "../../../project"

  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )

  # Only use prefix if it exists and is not empty
  name_prefix = try(local.merged_vars.name_prefix, "")
  # Use directory name for external IP naming with optional prefix
  base_ip_name = basename(get_terragrunt_dir())
  ip_name      = local.name_prefix != "" ? "${local.name_prefix}-${local.base_ip_name}" : local.base_ip_name

  # Region from the region configuration
  region = local.merged_vars.region
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/external_ip.hcl").inputs,
  local.merged_vars,
  {
    # Project and region configuration
    project_id = try(dependency.project.outputs.project_id, "mock-project-id")
    region     = local.region

    # External IP names - can reserve multiple IPs
    # Use pattern <project_name>-<parent_folder_name>
    names = ["${try(dependency.project.outputs.project_name, "mock-project-name")}-${basename(get_terragrunt_dir())}"]

    # External IP specific configuration
    address_type     = "EXTERNAL"
    global           = false # Regional IP for europe-west2
    ip_version       = "IPV4"
    environment_type = local.merged_vars.environment_type

    # Description
    description = "External IP for ${local.base_ip_name} in ${local.merged_vars.environment}"

    # Labels for resource management
    labels = merge(
      {
        component        = "external-ip"
        environment      = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
        purpose          = "sql-server"
        region           = local.region
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)
