# Firewall Rules for Web Server
# This creates firewall rules to allow HTTP and HTTPS traffic

# Include the firewall rules template
include "firewall_rules" {
  path = "${get_repo_root()}/_common/templates/firewall_rules.hcl"
}

# Dependencies
dependency "vpc-network" {
  config_path = "../../../example-vpc-network"
  
  mock_outputs = {
    network_name = "mock-network"
  }
  
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Load configurations
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
}

# Input variables for the module
inputs = {
  project_id   = local.project_vars.locals.project_name
  network_name = dependency.vpc-network.outputs.network_name
  
  rules = [
    {
      name        = "${local.project_vars.locals.project_name}-allow-http"
      description = "Allow HTTP traffic from anywhere"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["0.0.0.0/0"]
      target_tags = ["http-server", "web-server"]
      
      allow = [{
        protocol = "tcp"
        ports    = ["80"]
      }]
    },
    {
      name        = "${local.project_vars.locals.project_name}-allow-https"
      description = "Allow HTTPS traffic from anywhere"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["0.0.0.0/0"]
      target_tags = ["https-server", "web-server"]
      
      allow = [{
        protocol = "tcp"
        ports    = ["443"]
      }]
    },
    {
      name        = "${local.project_vars.locals.project_name}-allow-ssh-iap"
      description = "Allow SSH from Cloud IAP"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["35.235.240.0/20"]  # Cloud IAP range
      target_tags = ["web-server"]
      
      allow = [{
        protocol = "tcp"
        ports    = ["22"]
      }]
    }
  ]
}