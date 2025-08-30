# ArgoCD OAuth Client Secret
# This secret stores the OAuth client secret for ArgoCD authentication

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

include "secret_template" {
  path = "${get_repo_root()}/_common/templates/secret_manager.hcl"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.common_vars.locals
  )
  
  # Extract secret name from directory path
  secret_name = basename(get_terragrunt_dir())
}

dependency "project" {
  config_path = find_in_parent_folders("project")
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  project_id = dependency.project.outputs.project_id
  
  # Secret configuration
  secret_id = local.secret_name
  
  # Replication policy
  replication = {
    user_managed = {
      replicas = [
        {
          location = local.merged_vars.region
        }
      ]
    }
  }
  
  # Secret data - should be provided via environment variable or manual creation
  # The actual secret value should never be committed to the repository
  secret_data = get_env("ARGOCD_OAUTH_CLIENT_SECRET", "placeholder-value-update-manually")
  
  # Labels
  labels = merge(
    {
      managed_by  = "terragrunt"
      component   = "gke"
      application = "argocd"
      type        = "oauth"
      environment = local.merged_vars.environment
    },
    try(local.merged_vars.org_labels, {}),
    try(local.merged_vars.env_labels, {})
  )
  
  # Description
  secret_description = "OAuth client secret for ArgoCD authentication in ${local.merged_vars.environment} environment"
}