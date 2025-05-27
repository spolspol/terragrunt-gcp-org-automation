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

dependency "vpc-network" {
  config_path = "../../../../vpc-network"
  mock_outputs = {
    network_name = "mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../../project"
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
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/firewall_rules.hcl").inputs,
  {
    project_id   = dependency.project.outputs.project_id
    network_name = dependency.vpc-network.outputs.network_name

    rules = [
      {
        name        = "gke-master-to-webhook"
        description = "Allow GKE master to communicate with admission webhooks"
        direction   = "INGRESS"
        priority    = 1000
        ranges      = ["172.16.0.32/28"] # GKE master CIDR
        ports = {
          tcp = ["443", "8443", "9443", "15017"] # Common webhook ports
        }
        target_tags = ["gke-node"]
        allow = [{
          protocol = "tcp"
          ports    = ["443", "8443", "9443", "15017"]
        }]
        deny = []
        log_config = {
          metadata = "INCLUDE_ALL_METADATA"
        }
      }
    ]
  }
)