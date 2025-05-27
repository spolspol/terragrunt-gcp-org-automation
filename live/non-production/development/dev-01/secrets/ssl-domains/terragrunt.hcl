# SSL Domains Secret
# Comma-separated list of domains for SSL certificate generation

# Include the secret manager template
include "secret_manager" {
  path = "${get_repo_root()}/_common/templates/secret_manager.hcl"
}

# Load configurations
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  secrets_vars = read_terragrunt_config(find_in_parent_folders("secrets.hcl"))
}

# Input variables for the module
inputs = {
  project_id = local.project_vars.locals.project_name
  
  # Secret configuration
  secrets = [
    {
      name        = "ssl-domains"
      secret_data = "example.com,www.example.com"  # Replace with actual domains
    }
  ]
  
  # Labels
  labels = merge(
    local.account_vars.locals.org_labels,
    local.env_vars.locals.env_labels,
    local.secrets_vars.locals.secret_config.default_labels,
    {
      purpose = "ssl-certificate"
      type    = "domains"
    }
  )
}