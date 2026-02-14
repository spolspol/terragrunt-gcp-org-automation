# Cloud DNS Zone Template
# Provides standardized DNS zone configuration for global zones
# Include this template in your Terragrunt configurations for consistent DNS zone setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-cloud-dns.git?ref=${local.module_versions.cloud_dns}"
}

locals {
  # Get module versions and common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Read DNS configuration from parent dns.hcl if it exists
  dns_vars = try(read_terragrunt_config(find_in_parent_folders("dns.hcl")), {})

  # Extract zone name from directory
  zone_name = basename(get_terragrunt_dir())

  # Replace dots and other invalid characters with dashes for GCP resource naming
  zone_resource_name = replace(replace(local.zone_name, ".", "-"), "_", "-")

  # Default DNS configuration
  default_dns_config = {
    type                               = "public"
    kind                               = "dns#managedZone"
    visibility                         = "public"
    description                        = "Managed by Terragrunt"
    ttl                                = 300
    enable_dnssec                      = true
    dnssec_algorithm                   = "rsasha256"
    recordsets                         = []
    target_name_servers                = []
    target_network                     = ""
    peering_config                     = []
    forwarding_config                  = []
    private_visibility_config_networks = []
    labels                             = {}
  }

  # Merge configurations with precedence: inputs > dns_vars > defaults
  dns_config = merge(
    local.default_dns_config,
    try(local.dns_vars.locals, {})
  )
}

dependency "project" {
  config_path = "../../../project"

  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  project_id  = dependency.project.outputs.project_id
  type        = local.dns_config.type
  name        = local.zone_resource_name
  domain      = lookup(local.dns_config, "domain", "${local.zone_name}.")
  description = local.dns_config.description
  visibility  = local.dns_config.visibility

  # DNSSEC configuration
  dnssec_config = local.dns_config.enable_dnssec ? {
    state = "on"
    default_key_specs = [
      {
        algorithm  = local.dns_config.dnssec_algorithm
        key_type   = "keySigning"
        key_length = 2048
      },
      {
        algorithm  = local.dns_config.dnssec_algorithm
        key_type   = "zoneSigning"
        key_length = 1024
      }
    ]
  } : null

  # DNS records
  recordsets = local.dns_config.recordsets

  # Labels for resource management
  labels = merge(
    local.common_vars.locals.labels,
    local.dns_config.labels,
    {
      zone_type  = local.dns_config.type
      managed_by = "terragrunt"
      project    = dependency.project.outputs.project_name
      zone_name  = local.zone_resource_name
    }
  )

  target_name_servers                = local.dns_config.target_name_servers
  target_network                     = local.dns_config.target_network
  peering_config                     = local.dns_config.peering_config
  forwarding_config                  = local.dns_config.forwarding_config
  private_visibility_config_networks = local.dns_config.private_visibility_config_networks
}
