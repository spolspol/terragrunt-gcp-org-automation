# NAT Gateway Firewall Rules
# Allows egress traffic for NAT-enabled resources

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

include "firewall_template" {
  path = "${get_repo_root()}/_common/templates/firewall_rules.hcl"
}

include "firewall_config" {
  path = "../firewall.hcl"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")
  firewall_vars = read_terragrunt_config("../firewall.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )
  
  # Dynamic path construction for VPC network
  project_base_path = dirname(dirname(dirname(dirname(get_terragrunt_dir()))))
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
    network_name = "mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  project_id   = dependency.project.outputs.project_id
  network_name = dependency.vpc-network.outputs.network_name
  
  # Firewall rules for NAT gateway
  rules = [
    # Allow egress traffic for NAT-enabled resources
    {
      name        = "${dependency.project.outputs.project_name}-allow-nat-egress"
      description = "Allow egress traffic for NAT-enabled resources"
      direction   = "EGRESS"
      priority    = 1000
      ranges      = ["0.0.0.0/0"]
      target_tags = local.firewall_vars.locals.nat_config.nat_tags
      
      allow = [
        {
          protocol = "tcp"
          ports    = local.firewall_vars.locals.nat_config.nat_egress_ports.tcp
        },
        {
          protocol = "udp"
          ports    = local.firewall_vars.locals.nat_config.nat_egress_ports.udp
        },
        {
          protocol = "icmp"
        }
      ]
      
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    
    # Allow internal communication between NAT-enabled resources
    {
      name        = "${dependency.project.outputs.project_name}-allow-nat-internal"
      description = "Allow internal communication between NAT-enabled resources"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      target_tags = local.firewall_vars.locals.nat_config.nat_tags
      source_tags = local.firewall_vars.locals.nat_config.nat_tags
      
      allow = [
        {
          protocol = "tcp"
        },
        {
          protocol = "udp"
        },
        {
          protocol = "icmp"
        }
      ]
      
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    }
  ]
}