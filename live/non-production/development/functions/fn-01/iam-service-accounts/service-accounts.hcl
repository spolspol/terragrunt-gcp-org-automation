# Common configuration for all service accounts in fn-01

locals {
  common_dependencies = {
    project_path = "../../project"
  }

  common_mock_outputs = {
    project = {
      project_id            = "mock-project-id"
      service_account_email = "mock-sa@mock-project.iam.gserviceaccount.com"
    }
  }

  common_sa_labels = {
    component  = "service-account"
    managed_by = "terragrunt"
  }

  environment_sa_settings = {
    production = {
      generate_keys = false
    }
    non-production = {
      generate_keys = false
    }
  }
}
