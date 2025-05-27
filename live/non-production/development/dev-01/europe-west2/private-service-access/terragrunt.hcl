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

include "private_service_access_template" {
  path = "${get_repo_root()}/_common/templates/private_service_access.hcl"
}

# Dependency on the VPC network module (now at project level)
dependency "network" {
  config_path = "../../vpc-network"

  mock_outputs = {
    network_name      = "mock-network"
    network_self_link = "projects/mock-project/global/networks/mock-network"
    project_id        = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Dependency on the project module
dependency "project" {
  config_path = "../../project"

  mock_outputs = {
    project_id = "mock-project-id"
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
  # Use folder name for private service access naming with optional prefix
  base_psa_name = basename(get_terragrunt_dir())
  psa_name      = local.name_prefix != "" ? "${local.name_prefix}-${local.base_psa_name}" : local.base_psa_name

  # Private service access configuration
  private_ip_range_name = local.psa_name

  # Environment-specific IP ranges for private service access
  private_service_cidrs = {
    production = {
      ip_cidr_range = "10.1.0.0/16" # Larger range for production
    }
    non-production = {
      ip_cidr_range = "10.11.0.0/16" # Smaller range for non-production
    }
  }

  selected_cidr = lookup(
    local.private_service_cidrs,
    local.merged_vars.environment_type,
    local.private_service_cidrs["non-production"]
  )
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/private_service_access.hcl").inputs,
  local.merged_vars,
  {
    # Project and network configuration
    project_id = dependency.project.outputs.project_id
    network    = dependency.network.outputs.network_name

    # Required by the Coalfire module:
    peering_range = local.selected_cidr.ip_cidr_range
    name          = "${local.private_ip_range_name}-connection"

    # Private IP range configuration for Cloud SQL and other Google services
    private_ip_name        = local.private_ip_range_name
    private_ip_cidr        = local.selected_cidr.ip_cidr_range
    private_ip_description = "Private service access range for Cloud SQL and other Google services in ${local.merged_vars.environment}"
    environment_type       = local.merged_vars.environment_type

    # Labels for resource management
    labels = merge(
      {
        component        = "private-service-access"
        environment      = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
        name_prefix      = local.name_prefix
        purpose          = "cloud-sql-peering"
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)
