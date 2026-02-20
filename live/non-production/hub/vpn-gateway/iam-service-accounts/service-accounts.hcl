# Common service account configuration for all SAs in this project
# Include this in individual SA directories: find_in_parent_folders("service-accounts.hcl")

locals {
  # Common dependencies that all service accounts need
  common_dependencies = {
    project_path = "../project"
  }

  # Common mock outputs for dependencies
  common_mock_outputs = {
    project = {
      project_id = "mock-project-id"
    }
  }

  # Common labels that apply to all service accounts
  common_sa_labels = {
    component   = "service-account"
    managed_by  = "terragrunt"
    environment = "hub"
    project     = "vpn-gateway"
  }

  # Environment-specific settings for service accounts
  environment_sa_settings = {
    production = {
      generate_keys = false
    }
    non-production = {
      generate_keys = false
    }
  }
}
