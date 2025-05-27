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
  path = "${get_terragrunt_dir()}/../firewall.hcl"
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

# No additional dependencies needed - firewall rules run after vpc-network but before compute

locals {
  account_vars  = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars      = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars  = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars   = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars   = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")
  firewall_vars = read_terragrunt_config("${get_terragrunt_dir()}/../firewall.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )

  # Only use prefix if it exists and is not empty
  name_prefix = try(local.merged_vars.name_prefix, "")
  # Use the consolidated rule name
  rule_name = local.name_prefix != "" ? "${local.name_prefix}-${local.merged_vars.project}-sql-server-access" : "${local.merged_vars.project}-sql-server-access"

  # Region from the region configuration
  region = local.merged_vars.region
}

inputs = {
  # Project and network configuration - only variables expected by the firewall-rules module
  project_id   = try(dependency.project.outputs.project_id, "mock-project-id")
  network_name = try(dependency.network.outputs.network_name, "mock-network")

  # Consolidated firewall rules configuration
  rules = [
    {
      name                    = local.rule_name
      description             = "Consolidated access rule for SQL Server infrastructure in ${local.merged_vars.environment} - allows SSH, RDP, and SQL Server access"
      direction               = "INGRESS"
      priority                = 1000
      ranges                  = local.firewall_vars.locals.allowed_ip_ranges
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["sql-server"]
      target_service_accounts = null
      allow = [
        {
          protocol = "tcp"
          ports    = ["22"] # SSH access
        },
        {
          protocol = "tcp"
          ports    = ["1433"] # SQL Server access
        },
        {
          protocol = "tcp"
          ports    = ["3389"] # RDP access
        }
      ]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
      disabled = false
    }
  ]
}
