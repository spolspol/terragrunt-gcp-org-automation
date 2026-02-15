# DNS peering zone - forwards to DNS hub

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_dns_peering_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns_peering.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "network" {
  config_path = "../../../../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock-project/global/networks/mock-network"
    network_name      = "mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name    = try(dependency.project.outputs.project_name, "dp-dev-01")
  peering_domain  = "internal.example.com."
  zone_name       = "${local.project_name}-peering-${replace(trimsuffix(local.peering_domain, "."), ".", "-")}"
  dns_hub_network = "projects/org-dns-hub/global/networks/org-dns-hub-vpc-network"
}

inputs = {
  project_id = dependency.project.outputs.project_id

  name   = local.zone_name
  domain = local.peering_domain
  type   = "peering"

  private_visibility_config_networks = [
    dependency.network.outputs.network_self_link
  ]

  target_network = local.dns_hub_network

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "dns-peering"
      purpose   = "hub-forwarding"
    }
  )
}
