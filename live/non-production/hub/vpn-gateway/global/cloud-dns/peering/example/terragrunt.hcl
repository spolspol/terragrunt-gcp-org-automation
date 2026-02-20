include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "dns_peering_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns_peering.hcl"
  merge_strategy = "deep"
}

dependency "project_info" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "target_network" {
  config_path = "${get_repo_root()}/live/non-production/development/platform/dp-dev-01/vpc-network"
  mock_outputs = {
    network_self_link = "https://www.googleapis.com/compute/v1/projects/dp-dev-01/global/networks/dp-dev-01-vpc-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "consumer_network" {
  config_path = "${get_repo_root()}/live/non-production/hub/vpn-gateway/vpc-network"
  mock_outputs = {
    network_self_link = "https://www.googleapis.com/compute/v1/projects/org-vpn-gateway/global/networks/org-vpn-gateway-vpc"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

locals {
  peering_defaults = read_terragrunt_config("../peering.hcl")
}

inputs = {
  domain         = "dp-dev-01.example.io."
  description    = "Peering zone exposing dp-dev-01 private DNS to VPN clients"
  project_id     = dependency.project_info.outputs.project_id
  target_network = dependency.target_network.outputs.network_self_link
  private_visibility_config_networks = [
    dependency.consumer_network.outputs.network_self_link
  ]

  labels = merge(
    local.peering_defaults.locals.labels,
    {
      project     = "dp-dev-01"
      environment = "development"
    }
  )
}
