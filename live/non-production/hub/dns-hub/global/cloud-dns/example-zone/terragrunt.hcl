include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "dns_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns.hcl"
  merge_strategy = "deep"
}

locals {
  dns_vars   = read_terragrunt_config("../dns.hcl")
  dns_labels = local.dns_vars.locals.dns_labels
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id   = "org-dns-hub"
    project_name = "org-dns-hub"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "vpn_gateway_network" {
  config_path = "${get_repo_root()}/live/non-production/hub/vpn-gateway/vpc-network"
  mock_outputs = {
    network_self_link = "https://www.googleapis.com/compute/v1/projects/org-vpn-gateway/global/networks/org-vpn-gateway-vpc"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  domain      = "dev.example.io."
  description = "Private DNS zone for shared private records served to VPN clients"

  type       = "private"
  visibility = "private"

  private_visibility_config_networks = [
    dependency.vpn_gateway_network.outputs.network_self_link
  ]

  dnssec_config = null

  recordsets = [
    {
      name    = "development"
      type    = "CNAME"
      ttl     = 300
      records = ["cluster-02.ew2.dev-01.dev.example.io."]
    }
  ]

  labels = merge(
    local.dns_labels,
    {
      environment = "hub"
      project     = "dns-hub"
      zone_type   = "private"
      scope       = "vpn"
    }
  )
}
