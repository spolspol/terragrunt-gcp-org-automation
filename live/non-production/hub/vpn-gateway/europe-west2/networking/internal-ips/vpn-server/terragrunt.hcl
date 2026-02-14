include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "internal_ip_template" {
  path           = "${get_repo_root()}/_common/templates/internal_ip.hcl"
  merge_strategy = "deep"
}

dependency "network" {
  config_path = "../../../../vpc-network"
  mock_outputs = {
    network_self_link = "projects/org-vpn-gateway/global/networks/org-vpn-gateway-vpc"
    subnets_self_links = [
      "projects/org-vpn-gateway/regions/europe-west2/subnetworks/vpn-gateway-subnet",
      "projects/org-vpn-gateway/regions/europe-west2/subnetworks/vpn-server-subnet"
    ]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  networking_config    = read_terragrunt_config("${get_terragrunt_dir()}/../../networking.hcl")
  reserved_ip_config   = try(local.networking_config.locals.reserved_internal_ips[basename(get_terragrunt_dir())], null)
  reserved_ip_address  = try(local.reserved_ip_config.address, "10.11.2.10")
  subnetwork_index     = try(local.reserved_ip_config.subnetwork_index, 1)
  reserved_description = try(local.reserved_ip_config.description, "Reserved internal IP for ${basename(get_terragrunt_dir())}")
}

inputs = {
  project_id = try(dependency.project.outputs.project_id, "org-vpn-gateway")
  region     = include.base.locals.region
  names      = ["${try(dependency.project.outputs.project_id, "org-vpn-gateway")}-${basename(get_terragrunt_dir())}-internal"]

  subnetwork  = "projects/${try(dependency.project.outputs.project_id, "org-vpn-gateway")}/regions/${include.base.locals.region}/subnetworks/vpn-server-subnet"
  addresses   = [local.reserved_ip_address]
  description = "${local.reserved_description}"

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "internal-ip"
      purpose   = "vpn-server"
    }
  )
}
