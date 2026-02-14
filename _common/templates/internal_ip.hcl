# Internal IP Template
# Provides standardized reservation of internal IP addresses

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-address.git//?ref=${local.module_versions.address}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Default internal IP configuration
  default_internal_ip_config = {
    project_id   = null # Must be supplied by child config
    region       = null # Must be supplied by child config
    address_type = "INTERNAL"
    global       = false
    ip_version   = "IPV4"
    purpose      = null
    subnetwork   = null
  }
}

inputs = {
  # Required parameters to be provided by consuming Terragrunt configs
  project_id = null
  region     = null
  names      = []

  # Internal IP defaults (can be overridden by child configurations)
  address_type = try(inputs.address_type, local.default_internal_ip_config.address_type)
  global       = try(inputs.global, local.default_internal_ip_config.global)
  ip_version   = try(inputs.ip_version, local.default_internal_ip_config.ip_version)
  subnetwork   = try(inputs.subnetwork, local.default_internal_ip_config.subnetwork)
  purpose      = try(inputs.purpose, local.default_internal_ip_config.purpose)

  # Optional list of concrete IPs to reserve (empty list allows auto-allocation)
  addresses = try(inputs.addresses, [])

  # Labels applied to the reservation resource
  labels = try(inputs.labels, {
    managed_by = "terragrunt"
    component  = "internal-ip"
  })

  # Resource description propagated to the reservation
  description = try(inputs.description, "Internal IP managed by Terragrunt")
}
