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

include "cloud_sql_template" {
  path = "${get_repo_root()}/_common/templates/cloud_sql.hcl"
}

dependency "vpc-network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name            = "default"
    network_self_link       = "projects/mock-project/global/networks/default"
    subnets_self_links      = ["projects/mock-project/regions/europe-west2/subnetworks/default"]
    private_service_connect = "projects/mock-project/regions/europe-west2/serviceAttachments/mock-attachment"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "private_service_access" {
  config_path = "../../private-service-access"
  mock_outputs = {
    google_compute_global_address_name = "mock-private-ip-range"
    address                            = "10.11.0.0"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Commented out because ../iam does not exist and causes errors
# dependency "iam" {
#   config_path = "../iam"
#   mock_outputs = {
#     sql_service_account = "mock-sql-sa@mock-project.iam.gserviceaccount.com"
#   }
#   mock_outputs_allowed_terraform_commands = ["validate", "plan"]
# }

dependency "project" {
  config_path = "../../../project"
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
  common_vars  = read_terragrunt_config("${get_terragrunt_dir()}/../../../../../../../_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )

  # Only use prefix if it exists and is not empty
  name_prefix = try(local.merged_vars.name_prefix, "")
  # Use folder name for SQL Server naming with optional prefix
  base_sqlserver_name = basename(get_terragrunt_dir())
  sqlserver_name      = local.name_prefix != "" ? "${local.name_prefix}-${local.base_sqlserver_name}" : local.base_sqlserver_name
  selected_env_config = lookup(local.merged_vars.sqlserver_settings, local.merged_vars.environment_type, {})
}

inputs = merge(
  local.selected_env_config,
  {
    name       = replace(local.sqlserver_name, "_", "-")
    project_id = dependency.project.outputs.project_id
    region     = local.merged_vars.region

    # Explicitly set MSSQL 2022 Web Edition
    database_version = "SQLSERVER_2022_WEB"

    # Use private networking for SQL Server with private service access
    ip_configuration = merge(
      try(local.selected_env_config.ip_configuration, {}),
      {
        private_network     = dependency.vpc-network.outputs.network_self_link
        require_ssl         = true
        ipv4_enabled        = false
        allocated_ip_range  = dependency.private_service_access.outputs.google_compute_global_address_name
        authorized_networks = []
      }
    )

    # Database configuration - explicitly set what we need
    additional_databases = [
      {
        name      = "main"
        charset   = "UTF8"
        collation = "SQL_Latin1_General_CP1_CI_AS"
      },
      {
        name      = "reporting"
        charset   = "UTF8"
        collation = "SQL_Latin1_General_CP1_CI_AS"
      }
    ]

    # Users configuration
    additional_users = [
      {
        name            = "app_user"
        password        = ""
        random_password = true
      }
    ]

    # Deletion protection
    deletion_protection_enabled = false

    # Resource Labels
    user_labels = merge(
      {
        component        = "cloud-sql"
        database_type    = "mssql"
        edition          = "web"
        environment      = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
        name_prefix      = local.name_prefix
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)
