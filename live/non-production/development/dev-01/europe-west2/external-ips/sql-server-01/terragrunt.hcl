# SQL Server External IP Configuration
# This reserves an external IP address for SQL Server access

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

  # Extract resource name from directory path
  resource_name = basename(get_terragrunt_dir())
  
  # Dynamic path construction for dependencies
  project_base_path = dirname(dirname(dirname(get_terragrunt_dir())))
  vpc_network_path = "${local.project_base_path}/vpc-network"
}

dependency "project" {
  config_path = find_in_parent_folders("project")
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "vpc-network" {
  config_path = local.vpc_network_path
  mock_outputs = {
    network_name      = "mock-network"
    network_self_link = "projects/mock-project/global/networks/mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/external_ip.hcl").inputs,
  local.merged_vars,
  {
    project_id = dependency.project.outputs.project_id
    region     = local.merged_vars.region
    
    # External IP names - can reserve multiple IPs
    names = ["${dependency.project.outputs.project_name}-${local.resource_name}"]
    
    # External IP specific configuration
    address_type = "EXTERNAL"
    global       = false # Regional IP
    ip_version   = "IPV4"
    network_tier = "PREMIUM"
    
    # Description
    description = "External IP for SQL Server ${local.resource_name} in ${local.merged_vars.environment} environment"
    
    # Labels
    labels = merge(
      {
        managed_by   = "terragrunt"
        component    = "compute"
        type         = "sql-server"
        purpose      = "database"
        environment  = local.merged_vars.environment
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)