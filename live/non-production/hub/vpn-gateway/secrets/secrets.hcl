# Common configuration for all secrets in this directory

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  module_versions = local.common_vars.locals.module_versions

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.common_vars.locals
  )

  # Common secret labels
  common_secret_labels = {
    environment = local.env_vars.locals.environment
    project     = local.project_vars.locals.project_id
    managed_by  = "terragrunt"
    purpose     = "vpn-gateway"
  }
}
