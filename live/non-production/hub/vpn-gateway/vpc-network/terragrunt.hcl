include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "network_template" {
  path           = "${get_repo_root()}/_common/templates/network.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../project"
  mock_outputs = {
    project_id = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  project_id                             = dependency.project.outputs.project_id
  network_name                           = "${dependency.project.outputs.project_id}-vpc"
  routing_mode                           = "GLOBAL"
  shared_vpc_host                        = false
  delete_default_internet_gateway_routes = false
  mtu                                    = 1460

  # Subnets for VPN Gateway infrastructure
  subnets = [
    {
      subnet_name           = "vpn-gateway-subnet"
      subnet_ip             = "10.11.1.0/24"
      subnet_region         = "europe-west2"
      subnet_private_access = true
      subnet_flow_logs      = true
      description           = "HA VPN gateway and Cloud NAT subnet"
    },
    {
      subnet_name           = "vpn-server-subnet"
      subnet_ip             = "10.11.2.0/24"
      subnet_region         = "europe-west2"
      subnet_private_access = true
      subnet_flow_logs      = true
      description           = "VPN server subnet"
    },
    {
      subnet_name           = "vpn-default-pool"
      subnet_ip             = "10.11.100.0/24"
      subnet_region         = "europe-west2"
      subnet_private_access = false
      subnet_flow_logs      = false
      description           = "Reserved address space for default VPN client pool"
    },
    {
      subnet_name           = "vpn-admin-pool"
      subnet_ip             = "10.11.101.0/24"
      subnet_region         = "europe-west2"
      subnet_private_access = false
      subnet_flow_logs      = false
      description           = "Reserved address space for administrative VPN pool"
    },
    {
      subnet_name           = "vpn-dmz-pool"
      subnet_ip             = "10.11.111.0/24"
      subnet_region         = "europe-west2"
      subnet_private_access = false
      subnet_flow_logs      = false
      description           = "Reserved address space for DMZ-restricted VPN pool"
    }
  ]

  secondary_ranges = {}
  routes           = []
  firewall_rules   = []
}
