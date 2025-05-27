# Static Content Bucket for Web Server
# This bucket stores the static website files served by nginx

# Include the cloud storage template
include "cloud_storage" {
  path = "${get_repo_root()}/_common/templates/cloud_storage.hcl"
}

# Load configurations
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

# Input variables for the module
inputs = {
  project_id = local.project_vars.locals.project_name
  prefix     = local.project_vars.locals.project_name
  
  names = ["static-content"]
  
  # Standard storage for frequently accessed content
  storage_class = "STANDARD"
  
  # Bucket location
  location = local.region_vars.locals.region
  
  # Enable versioning for content history
  versioning = {
    enabled = true
  }
  
  # Force destroy allowed in non-production
  force_destroy = local.env_vars.locals.environment_type != "production"
  
  # Uniform bucket-level access (recommended)
  bucket_policy_only = {
    enabled = true
  }
  
  # Labels
  labels = merge(
    local.account_vars.locals.org_labels,
    local.env_vars.locals.env_labels,
    {
      component = "web-server"
      purpose   = "static-content"
      content   = "website-files"
    }
  )
  
  # Lifecycle rules for non-production environments
  lifecycle_rules = local.env_vars.locals.environment_type != "production" ? [
    {
      action = {
        type = "Delete"
      }
      condition = {
        age        = 90  # Delete old versions after 90 days
        with_state = "ARCHIVED"
      }
    }
  ] : []
}