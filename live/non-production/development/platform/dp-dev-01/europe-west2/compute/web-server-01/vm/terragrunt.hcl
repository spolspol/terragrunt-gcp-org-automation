# Web Server VM Instance
# This creates the actual compute instance from the template

# Include the compute instance configuration
include "compute_instance" {
  path = "${get_repo_root()}/_common/templates/compute_instance.hcl"
}

# Dependencies
dependency "instance_template" {
  config_path = "../"

  mock_outputs = {
    self_link             = "mock-template-link"
    name                  = "mock-template-name"
    service_account_email = "mock-sa@example.iam.gserviceaccount.com"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "external_ip" {
  config_path = "../../../external-ips/web-server-ip"

  mock_outputs = {
    addresses = {
      "web-server-ip" = "10.0.0.1"
    }
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
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
  zone       = local.region_vars.locals.zones[0]
  name       = "${local.project_vars.locals.project_name}-web-server-01"
  hostname   = "web-server-01.${local.project_vars.locals.project_name}.internal"

  # Use the instance template
  instance_template = dependency.instance_template.outputs.self_link

  # Network configuration
  access_config = [{
    nat_ip       = dependency.external_ip.outputs.addresses["web-server-ip"]
    network_tier = "PREMIUM"
  }]

  # Labels
  labels = merge(
    local.account_vars.locals.org_labels,
    local.env_vars.locals.env_labels,
    {
      component     = "web-server"
      purpose       = "static-website"
      instance_type = "nginx"
    }
  )
}
