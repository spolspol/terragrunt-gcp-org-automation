# IAM Bindings for Linux Server Service Account
# This grants necessary permissions to the linux server's service account

# Include the IAM bindings template
include "iam_bindings" {
  path = "${get_repo_root()}/_common/templates/iam_bindings.hcl"
}

# Dependencies
dependency "instance_template" {
  config_path = "../"

  mock_outputs = {
    service_account_email = "mock-sa@example.iam.gserviceaccount.com"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "project" {
  config_path = "../../../../project"

  mock_outputs = {
    project_id = "mock-project-id"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Load configurations
locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
}

# Input variables for the IAM module
inputs = {
  project_id = local.project_vars.locals.project_name
  mode       = "additive"

  bindings = {
    # Secret Manager access for application secrets
    "roles/secretmanager.secretAccessor" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_email}"
    ]

    # Storage access for application data
    "roles/storage.objectAdmin" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_email}"
    ]

    # Logging permissions
    "roles/logging.logWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_email}"
    ]

    # Monitoring permissions
    "roles/monitoring.metricWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_email}"
    ]
  }
}
