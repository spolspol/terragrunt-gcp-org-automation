# Project-level IAM bindings
# This configures project-wide IAM permissions

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "project" {
  path = find_in_parent_folders("project.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "iam_template" {
  path = "${get_repo_root()}/_common/templates/iam_bindings.hcl"
}

# Dependency on the project
dependency "project" {
  config_path = "../project"
  
  mock_outputs = {
    project_id = "mock-project-id"
    service_account_email = "terraform-sa@mock-project-id.iam.gserviceaccount.com"
  }
  
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
}

inputs = {
  projects = [dependency.project.outputs.project_id]
  mode     = "additive"
  
  bindings = {
    # Project Editor for Terraform service account
    "roles/editor" = [
      "serviceAccount:${dependency.project.outputs.service_account_email}"
    ]
    
    # Security Admin for managing IAM
    "roles/iam.securityAdmin" = [
      "serviceAccount:${dependency.project.outputs.service_account_email}"
    ]
    
    # Service Account Admin for creating service accounts
    "roles/iam.serviceAccountAdmin" = [
      "serviceAccount:${dependency.project.outputs.service_account_email}"
    ]
    
    # Compute Admin for managing compute resources
    "roles/compute.admin" = [
      "serviceAccount:${dependency.project.outputs.service_account_email}"
    ]
    
    # Storage Admin for managing buckets
    "roles/storage.admin" = [
      "serviceAccount:${dependency.project.outputs.service_account_email}"
    ]
    
    # Secret Manager Admin for managing secrets
    "roles/secretmanager.admin" = [
      "serviceAccount:${dependency.project.outputs.service_account_email}"
    ]
  }
}