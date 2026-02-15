include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "vpc_peering_template" {
  path           = "${get_repo_root()}/_common/templates/vpc_peering.hcl"
  merge_strategy = "deep"
}

dependency "vpn_vpc" {
  config_path = "../../../../vpc-network"

  mock_outputs = {
    network_name      = "org-vpn-gateway-vpc"
    network_self_link = "projects/org-vpn-gateway/global/networks/org-vpn-gateway-vpc"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "peer_vpc" {
  config_path = "${get_repo_root()}/live/non-production/development/platform/dp-dev-01/vpc-network"

  mock_outputs = {
    network_name      = "dp-dev-01-vpc"
    network_self_link = "projects/dp-dev-01/global/networks/dp-dev-01-vpc"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  local_network = dependency.vpn_vpc.outputs.network_self_link
  peer_network  = dependency.peer_vpc.outputs.network_self_link

  export_local_custom_routes                = false
  export_peer_custom_routes                 = true
  export_local_subnet_routes_with_public_ip = false
  export_peer_subnet_routes_with_public_ip  = false
  stack_type                                = "IPV4_ONLY"
}
