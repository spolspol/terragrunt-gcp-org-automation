# Common secrets configuration for all secrets in network-hub

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

  common_secret_settings = {
    rotation_period = "7776000s" # 90 days
  }

  common_secret_roles = [
    "roles/secretmanager.secretAccessor",
    "roles/secretmanager.viewer"
  ]

  common_secret_labels = {
    component  = "secret-manager"
    managed_by = "terragrunt"
    purpose    = "network-hub"
  }

  environment_secret_settings = {
    infrastructure = {
      deletion_protection = true
      rotation_enabled    = false
    }
  }
}
