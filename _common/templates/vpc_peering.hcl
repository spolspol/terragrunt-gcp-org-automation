# VPC Peering Template
# Wraps terraform-google-network network-peering submodule with shared defaults.

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-network.git//modules/network-peering?ref=${local.module_versions.network}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
}

inputs = {
  # Required identifiers for both sides of the peering (prefer self links)
  local_network = try(
    inputs.local_network,
    inputs.network_self_link_local,
    inputs.network_self_link,
    inputs.network_name_local,
    null
  )

  peer_network = try(
    inputs.peer_network,
    inputs.peer_network_self_link,
    inputs.peer_network_name,
    null
  )

  prefix = try(inputs.prefix, "network-peering")

  # Route exchange controls (defaults align with restrictive posture)
  export_local_custom_routes                = try(inputs.export_local_custom_routes, false)
  export_peer_custom_routes                 = try(inputs.export_peer_custom_routes, false)
  export_local_subnet_routes_with_public_ip = try(inputs.export_local_subnet_routes_with_public_ip, false)
  export_peer_subnet_routes_with_public_ip  = try(inputs.export_peer_subnet_routes_with_public_ip, false)

  # Stack type defaults to IPv4; override if dual-stack is required
  stack_type = try(inputs.stack_type, "IPV4_ONLY")

  # Optional labels and explicit dependencies
  module_depends_on = try(inputs.module_depends_on, [])
}
