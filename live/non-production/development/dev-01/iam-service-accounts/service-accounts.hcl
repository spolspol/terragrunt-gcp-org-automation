# Common configuration for all service accounts in this project
# Each service account has its own directory with a terragrunt.hcl

locals {
  # Common dependencies that all service accounts need
  common_dependencies = {
    project_path = "../../project"
  }

  # Common mock outputs for dependencies
  common_mock_outputs = {
    project = {
      project_id            = "mock-project-id"
      service_account_email = "mock-sa@mock-project.iam.gserviceaccount.com"
    }
  }

  # Common labels for all service accounts
  common_sa_labels = {
    component  = "service-account"
    managed_by = "terragrunt"
  }

  # Environment-specific settings
  environment_sa_settings = {
    production = {
      generate_keys = false
    }
    non-production = {
      generate_keys = false
    }
  }
}
