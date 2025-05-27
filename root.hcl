# Root Terragrunt Configuration for Stacks
# This is the root configuration that all units in the stack will inherit from.

# Remote state configuration - stores OpenTofu state in a GCS bucket
remote_state {
  backend = "gcs"
  config = {
    bucket   = "org-tofu-state"
    prefix   = "${path_relative_to_include()}"
    project  = "org-automation" # Bootstrap project for state storage
    location = "europe-west2"
  }

  # Enable state locking to prevent concurrent modifications
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Provider configuration is handled by each individual module using their inputs
# No common provider generation to avoid variable reference issues

# Define default inputs that will be merged with all child Terragrunt configurations
inputs = {}

# OpenTofu configuration
terraform_binary             = "tofu"
terraform_version_constraint = ">= 1.6.0"

# Extra arguments for terraform commands
terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
  }
}

# Note: Using CLI redesign features, not Terragrunt Stacks
# The stack block is not needed for CLI redesign experiment
