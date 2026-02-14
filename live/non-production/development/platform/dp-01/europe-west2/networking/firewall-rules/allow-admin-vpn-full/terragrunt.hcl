# Allow full access from admin VPN

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "firewall_template" {
  path           = "${get_repo_root()}/_common/templates/firewall_rules.hcl"
  merge_strategy = "deep"
}

include "firewall_config" {
  path = "${get_terragrunt_dir()}/../firewall.hcl"
}

dependency "network" {
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
  firewall_vars = read_terragrunt_config("${get_terragrunt_dir()}/../firewall.hcl")
  project_name  = include.base.locals.merged.project
}

inputs = {
  project_id   = dependency.project.outputs.project_id
  network_name = dependency.network.outputs.network_name

  rules = [
    {
      name        = "${local.project_name}-allow-admin-vpn-full"
      description = "Admin VPN pool full access to all resources"
      direction   = "INGRESS"
      priority    = 900
      ranges      = local.firewall_vars.locals.admin_vpn_ranges

      source_tags             = null
      source_service_accounts = null
      target_tags             = null
      target_service_accounts = null

      allow = [{
        protocol = "all"
        ports    = []
      }]

      deny = []

      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }

      disabled = false
    }
  ]
}
