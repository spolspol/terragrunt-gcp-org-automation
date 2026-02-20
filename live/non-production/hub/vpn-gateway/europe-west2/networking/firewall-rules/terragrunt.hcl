# Firewall rules for VPN Gateway
# This is a placeholder - individual rules should be created as subdirectories
# See the firewall_rules template for configuration patterns

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "firewall_template" {
  path           = "${get_repo_root()}/_common/templates/firewall_rules.hcl"
  merge_strategy = "deep"
}

dependency "network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name = "org-vpn-gateway-vpc"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  project_id   = dependency.project.outputs.project_id
  network_name = dependency.network.outputs.network_name

  rules = [
    {
      name        = "allow-iap-ssh"
      description = "Allow IAP SSH access"
      direction   = "INGRESS"
      priority    = 100
      ranges      = ["35.235.240.0/20"] # Google IAP range
      allow = [{
        protocol = "tcp"
        ports    = ["22"]
      }]
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    {
      name        = "allow-vpn-clients"
      description = "Allow VPN client connections"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["0.0.0.0/0"]
      allow = [{
        protocol = "udp"
        ports    = ["1194", "51820"]
      }]
      target_tags = ["vpn-server"]
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    {
      name        = "allow-https-vpn-ui"
      description = "Allow HTTPS access to VPN admin UI"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["0.0.0.0/0"]
      allow = [{
        protocol = "tcp"
        ports    = ["443"]
      }]
      target_tags = ["vpn-server"]
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    {
      name        = "allow-internal"
      description = "Allow internal VPC communication"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["10.11.0.0/16"]
      allow = [{
        protocol = "all"
      }]
    }
  ]
}
