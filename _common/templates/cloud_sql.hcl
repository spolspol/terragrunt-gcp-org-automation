# Cloud SQL Module Template
# This template provides standardized Cloud SQL instance configurations
# Include this template in your Terragrunt configurations for consistent Cloud SQL setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-sql-db.git//modules/mssql?ref=${local.module_versions.sql_db}"

  # Add before_hook for validation if needed
  before_hook "validate_inputs" {
    commands = ["apply", "plan"]
    execute  = ["echo", "Validating Cloud SQL inputs..."]
  }

  # Add after_hook for notifications or other post-deployment tasks
  after_hook "notify_completion" {
    commands = ["apply"]
    execute  = ["echo", "Cloud SQL deployment completed!"]
  }
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default Cloud SQL configuration for MSSQL 2022 Web Edition
  default_cloud_sql_settings = {
    edition          = "WEB"
    database_version = "SQLSERVER_2022_WEB"

    # Default settings for SQL instances
    disk_autoresize = false
    disk_size       = 16 # GB
    disk_type       = "PD_SSD"

    # Default database flags
    database_flags = [
      {
        name  = "remote access"
        value = "on"
      },
      {
        name  = "contained database authentication"
        value = "on"
      },
      {
        name  = "cross db ownership chaining"
        value = "off"
      }
    ]
  }

  # Default databases to create
  default_databases = [
    {
      name      = "main"
      charset   = "UTF8"
      collation = "SQL_Latin1_General_CP1_CI_AS"
    }
  ]

  # Default users with read/write access
  default_users = [
    {
      name            = "app_user"
      password        = ""
      random_password = true
    }
  ]
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Use database version from the default config, allow override
  database_version = try(inputs.database_version, local.default_cloud_sql_settings.database_version)

  # Databases to create - override in specific implementations if needed
  additional_databases = try(inputs.additional_databases, local.default_databases)

  # Users to create - override in specific implementations if needed
  additional_users = try(inputs.additional_users, local.default_users)

  # Set specific configuration directly based on defaults
  disk_autoresize = try(inputs.disk_autoresize, local.default_cloud_sql_settings.disk_autoresize)
  disk_size       = try(inputs.disk_size, local.default_cloud_sql_settings.disk_size)
  disk_type       = try(inputs.disk_type, local.default_cloud_sql_settings.disk_type)
  database_flags  = try(inputs.database_flags, local.default_cloud_sql_settings.database_flags)

  # IP configuration defaults - override in specific implementations
  ip_configuration = try(inputs.ip_configuration, {
    ipv4_enabled        = true
    private_network     = null # Must be provided in specific implementation
    require_ssl         = true
    allocated_ip_range  = null
    authorized_networks = []
  })

  # High availability settings (should be overridden in consumer if needed)
  deletion_protection_enabled = try(inputs.deletion_protection_enabled, false)

  # Default Cloud SQL labels
  user_labels = try(inputs.user_labels, {
    managed_by  = "terragrunt"
    component   = "cloud-sql"
    environment = try(inputs.environment_type, "non-production")
  })
}
