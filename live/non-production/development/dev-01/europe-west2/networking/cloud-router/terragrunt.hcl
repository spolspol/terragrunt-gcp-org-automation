# Cloud Router Configuration
# Provides BGP routing for Cloud NAT

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

include "cloud_router_template" {
  path = "${get_repo_root()}/_common/templates/cloud-router.hcl"
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
  
  # Dynamic path construction for VPC network
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

inputs = {
  project_id = dependency.project.outputs.project_id
  region     = local.merged_vars.region
  
  # Router configuration
  router_name = "${dependency.project.outputs.project_name}-${local.merged_vars.region}-router"
  network     = dependency.vpc-network.outputs.network_name
  
  # BGP configuration
  bgp = {
    asn                = 64514
    advertise_mode     = "DEFAULT"
    advertised_groups  = ["ALL_SUBNETS"]
    keepalive_interval = 20
  }
  
  # Description
  description = "Cloud Router for NAT Gateway in ${local.merged_vars.environment} environment"
}