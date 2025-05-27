# External IP Address for Web Server
# This reserves a static external IP for the web server

# Include the external IP template
include "external_ip" {
  path = "${get_repo_root()}/_common/templates/external_ip.hcl"
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
  region     = local.region_vars.locals.region
  
  names = ["web-server-ip"]
  
  # Use PREMIUM tier for better performance
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  
  # Labels
  labels = merge(
    local.account_vars.locals.org_labels,
    local.env_vars.locals.env_labels,
    {
      component = "web-server"
      purpose   = "static-ip"
    }
  )
}