# Cluster Services External IP Configuration
# This reserves an external IP address for the GKE cluster ingress services

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

include "region" {
  path = find_in_parent_folders("region.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "address_template" {
  path = "${get_repo_root()}/_common/templates/address.hcl"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )

  # Extract resource name from directory path (cluster-01-services)
  resource_name = basename(get_terragrunt_dir())
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
  region     = local.merged_vars.region
  
  # IP address configuration
  address_name        = "${local.merged_vars.project_name}-${local.resource_name}"
  address_type        = "EXTERNAL"
  address_tier        = "PREMIUM"
  address_description = "External IP for GKE cluster ingress services in ${local.merged_vars.environment} environment"
  
  # Labels
  labels = merge(
    {
      managed_by  = "terragrunt"
      component   = "gke"
      type        = "ingress"
      cluster     = "cluster-01"
      environment = local.merged_vars.environment
    },
    try(local.merged_vars.org_labels, {}),
    try(local.merged_vars.env_labels, {})
  )
}