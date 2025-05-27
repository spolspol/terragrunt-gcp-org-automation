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

include "bucket_template" {
  path = "${get_repo_root()}/_common/templates/cloud_storage.hcl"
}

# Dependency on the project module
dependency "project" {
  config_path = "../../../project"

  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
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

  # Only use prefix if it exists and is not empty
  name_prefix = try(local.merged_vars.name_prefix, "")
  # Bucket naming: <project_name>-<bucket_folder_name>
  bucket_folder_name = basename(get_terragrunt_dir())

  # Region from the region configuration
  region = local.merged_vars.region
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/cloud_storage.hcl").inputs,
  {
    # Project and location configuration
    project_id = try(dependency.project.outputs.project_id, "mock-project-id")
    location   = local.region

    # Bucket names - using the standardized naming convention
    names = ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"]

    # Configuration for VM scripts storage
    storage_class            = "STANDARD"
    public_access_prevention = "enforced"
    randomize_suffix         = true

    # Environment-specific settings in map format for v11.0.0
    versioning = {
      for name in ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"] :
      lower(name) => true
    }
    force_destroy = {
      for name in ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"] :
      lower(name) => local.merged_vars.environment_type == "production" ? false : true
    }
    bucket_policy_only = {
      for name in ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"] :
      lower(name) => true
    }

    # Labels for resource management
    labels = merge(
      {
        component        = "storage"
        environment      = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
        name_prefix      = local.name_prefix
        purpose          = "vm-scripts"
        region           = local.region
        bucket_type      = "scripts"
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)