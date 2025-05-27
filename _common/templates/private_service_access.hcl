# Private Service Access Template
# This template provides standardized private service access configuration for GCP services
# Include this template in your Terragrunt configurations for consistent private service access setups

terraform {
  source = "git::https://github.com/Coalfire-CF/terraform-google-private-service-access.git//?ref=main"
}

locals {
  # Default private service access configuration
  default_private_service_config = {
    service = "servicenetworking.googleapis.com"

    # Default IP ranges for private service access
    default_ip_ranges = {
      production = {
        ip_cidr_range = "10.1.0.0/16" # Larger range for production
        prefix_length = 16
      }
      non-production = {
        ip_cidr_range = "10.11.0.0/16" # Smaller range for non-production
        prefix_length = 16
      }
    }
  }

  # Environment-specific settings
  env_private_service_configs = {
    production = {
      ip_cidr_range      = "10.1.0.0/16"
      prefix_length      = 16
      description_suffix = "for production Cloud SQL and other Google services"
    }
    non-production = {
      ip_cidr_range      = "10.11.0.0/16"
      prefix_length      = 16
      description_suffix = "for non-production Cloud SQL and other Google services"
    }
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  project_id = null # Must be provided in the child module
  network    = null # Must be provided in the child module

  # Private IP range configuration
  private_ip_name = try(inputs.private_ip_name, "private-service-access")

  # Environment-aware IP range selection
  private_ip_cidr = lookup(
    local.env_private_service_configs[try(inputs.environment_type, "non-production")],
    "ip_cidr_range",
    local.default_private_service_config.default_ip_ranges["non-production"].ip_cidr_range
  )

  # Description based on environment
  private_ip_description = try(
    inputs.private_ip_description,
    "Private service access range ${lookup(
      local.env_private_service_configs[try(inputs.environment_type, "non-production")],
      "description_suffix",
      "for Cloud SQL and other Google services"
    )}"
  )

  # Service networking configuration
  service = local.default_private_service_config.service

  # Default labels
  labels = try(inputs.labels, {
    managed_by = "terragrunt"
    component  = "private-service-access"
  })
}
