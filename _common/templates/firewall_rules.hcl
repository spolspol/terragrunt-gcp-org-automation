# Firewall Rules Template
# This template provides standardized firewall rule management
# Include this template in your Terragrunt configurations for consistent firewall setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-network.git//modules/firewall-rules?ref=${local.module_versions.firewall_rules}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default firewall rule configuration
  default_firewall_config = {
    project_id   = null # Must be provided in the child module
    network_name = null # Must be provided in the child module
    direction    = "INGRESS"
    priority     = 1000
    disabled     = false
  }

  # Environment-specific settings
  env_firewall_configs = {
    production = {
      priority = 900 # Higher priority for production
      disabled = false
    }
    non-production = {
      priority = 1000 # Standard priority for dev/test
      disabled = false
    }
  }

  # Common rule templates
  common_rules = {
    allow_ssh = {
      name                    = "allow-ssh"
      description             = "Allow SSH access"
      direction               = "INGRESS"
      priority                = 1000
      ranges                  = ["0.0.0.0/0"]
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["ssh"]
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["22"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    }
    allow_rdp = {
      name                    = "allow-rdp"
      description             = "Allow RDP access"
      direction               = "INGRESS"
      priority                = 1000
      ranges                  = ["0.0.0.0/0"]
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["rdp"]
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["3389"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    }
    allow_http = {
      name                    = "allow-http"
      description             = "Allow HTTP traffic"
      direction               = "INGRESS"
      priority                = 1000
      ranges                  = ["0.0.0.0/0"]
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["http-server"]
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["80"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    }
    allow_https = {
      name                    = "allow-https"
      description             = "Allow HTTPS traffic"
      direction               = "INGRESS"
      priority                = 1000
      ranges                  = ["0.0.0.0/0"]
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["https-server"]
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["443"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    }
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  project_id   = null # Must be provided
  network_name = null # Must be provided
  rules        = []   # List of firewall rules - must be provided

  # Optional parameters with defaults
  # Rules can reference local.common_rules for standard configurations

  # Example usage in child modules:
  # rules = [
  #   local.common_rules.allow_ssh,
  #   local.common_rules.allow_rdp,
  #   {
  #     name               = "custom-rule"
  #     description        = "Custom firewall rule"
  #     direction          = "INGRESS"
  #     priority           = 1000
  #     ranges             = ["10.0.0.0/8"]
  #     target_tags        = ["custom-tag"]
  #     allow = [{
  #       protocol = "tcp"
  #       ports    = ["8080"]
  #     }]
  #   }
  # ]
}
