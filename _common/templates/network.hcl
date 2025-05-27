# Network Module Template
# This template provides standardized VPC network and subnet configurations
# Include this template in your Terragrunt configurations for consistent network setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-network.git//?ref=${local.module_versions.network}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default network configuration
  default_network_config = {
    project_id                             = null # Must be provided in the child module
    network_name                           = null # Must be provided in the child module
    routing_mode                           = "GLOBAL"
    auto_create_subnetworks                = false
    delete_default_internet_gateway_routes = false
    mtu                                    = 1460
    description                            = "Managed by Terragrunt"
  }

  # Environment-specific settings
  env_network_configs = {
    production = {
      routing_mode                           = "GLOBAL"
      auto_create_subnetworks                = false
      delete_default_internet_gateway_routes = true
      mtu                                    = 1500
    }
    non-production = {
      routing_mode                           = "REGIONAL"
      auto_create_subnetworks                = false
      delete_default_internet_gateway_routes = false
      mtu                                    = 1460
    }
  }

  # Default subnet configuration
  default_subnets = [
    {
      subnet_name           = "default-subnet"
      subnet_ip             = "10.10.0.0/24"
      subnet_region         = null # Must be provided in the child module
      subnet_private_access = true
      subnet_flow_logs      = false
      description           = "Default subnet managed by Terragrunt"
    }
  ]
}

# Default inputs - these will be merged with specific configurations
inputs = {
  project_id   = try(inputs.project_id, local.default_network_config.project_id)
  network_name = try(inputs.network_name, local.default_network_config.network_name)
  routing_mode = lookup(
    local.env_network_configs[try(inputs.environment_type, "non-production")],
    "routing_mode",
    local.default_network_config.routing_mode
  )
  auto_create_subnetworks = lookup(
    local.env_network_configs[try(inputs.environment_type, "non-production")],
    "auto_create_subnetworks",
    local.default_network_config.auto_create_subnetworks
  )
  delete_default_internet_gateway_routes = lookup(
    local.env_network_configs[try(inputs.environment_type, "non-production")],
    "delete_default_internet_gateway_routes",
    local.default_network_config.delete_default_internet_gateway_routes
  )
  mtu = lookup(
    local.env_network_configs[try(inputs.environment_type, "non-production")],
    "mtu",
    local.default_network_config.mtu
  )
  description = try(inputs.description, local.default_network_config.description)

  # Subnets - override in specific implementations
  subnets = try(inputs.subnets, local.default_subnets)

  # Secondary ranges - override in specific implementations
  secondary_ranges = try(inputs.secondary_ranges, {})

  # Routes - override in specific implementations
  routes = try(inputs.routes, [])

  # Firewall rules - override in specific implementations
  firewall_rules = try(inputs.firewall_rules, [])

  # Labels
  network_labels = try(inputs.network_labels, {
    managed_by = "terragrunt"
    component  = "network"
  })
}
