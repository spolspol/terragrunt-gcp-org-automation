# External IP Template
# This template provides standardized external IP address reservation
# Include this template in your Terragrunt configurations for consistent external IP setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-address.git//?ref=${local.module_versions.external_ip}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default external IP configuration
  default_external_ip_config = {
    project_id   = null # Must be provided in the child module
    region       = null # Must be provided in the child module
    address_type = "EXTERNAL"
    global       = false # Use regional addresses by default
    ip_version   = "IPV4"
    network_tier = "PREMIUM"
    purpose      = null
    subnetwork   = null
  }

  # Environment-specific settings
  env_external_ip_configs = {
    production = {
      network_tier = "PREMIUM"
      ip_version   = "IPV4"
    }
    non-production = {
      network_tier = "STANDARD"
      ip_version   = "IPV4"
    }
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  project_id = null # Must be provided
  region     = null # Must be provided
  names      = []   # List of external IP names - must be provided

  # Optional parameters with defaults
  address_type = try(inputs.address_type, local.default_external_ip_config.address_type)
  global       = try(inputs.global, local.default_external_ip_config.global)
  ip_version   = try(inputs.ip_version, local.default_external_ip_config.ip_version)

  # Environment-specific network tier
  network_tier = lookup(
    local.env_external_ip_configs[try(inputs.environment_type, "non-production")],
    "network_tier",
    local.default_external_ip_config.network_tier
  )

  # Optional configuration
  purpose    = try(inputs.purpose, local.default_external_ip_config.purpose)
  subnetwork = try(inputs.subnetwork, local.default_external_ip_config.subnetwork)

  # Optional DNS configuration - leave empty by default
  enable_cloud_dns = try(inputs.enable_cloud_dns, false)
  dns_domain       = try(inputs.dns_domain, "")
  dns_managed_zone = try(inputs.dns_managed_zone, "")
  dns_record_ttl   = try(inputs.dns_record_ttl, 300)
  dns_short_names  = try(inputs.dns_short_names, [])

  # Labels
  labels = try(inputs.labels, {
    managed_by = "terragrunt"
    component  = "external-ip"
  })

  # Description
  description = try(inputs.description, "External IP managed by Terragrunt")
}
