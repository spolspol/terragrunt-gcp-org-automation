include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "external_ip_template" {
  path           = "${get_repo_root()}/_common/templates/external_ip.hcl"
  merge_strategy = "deep"
}

dependency "network" {
  config_path = "../../../../vpc-network"
  mock_outputs = {
    network_name      = "org-vpn-gateway-vpc"
    network_self_link = "projects/org-vpn-gateway/global/networks/org-vpn-gateway-vpc"
    project_id        = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id   = "org-vpn-gateway"
    project_name = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  project_id = dependency.project.outputs.project_id
  region     = include.base.locals.region

  # External IP name for VPN server
  names = ["${dependency.project.outputs.project_name}-${include.base.locals.resource_name}"]

  address_type     = "EXTERNAL"
  global           = false
  ip_version       = "IPV4"
  environment_type = try(include.base.locals.environment_type, "hub")

  description = "Static IP for VPN server"

  labels = {
    component   = "external-ip"
    cost_center = "infrastructure"
    environment = include.base.locals.environment
    purpose     = "vpn-server"
    region      = include.base.locals.region
    managed_by  = "terragrunt"
  }
}
