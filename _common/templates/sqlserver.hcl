# SQL Server Module Template
# This template provides standardized SQL Server instance configurations
# Include this template in your Terragrunt configurations for consistent SQL Server setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-sql-db.git//modules/mssql?ref=${local.module_versions.sql_db}"

  # Add before_hook for validation if needed
  before_hook "validate_inputs" {
    commands = ["apply", "plan"]
    execute  = ["echo", "Validating SQL Server inputs..."]
  }
  
  # Add after_hook for notifications or other post-deployment tasks
  after_hook "notify_completion" {
    commands = ["apply"]
    execute  = ["echo", "SQL Server deployment completed!"]
  }
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  # Default SQL Server configuration
  default_sqlserver_settings = {
    edition = "ENTERPRISE"
    database_version  = "SQLSERVER_2022_WEB"

    # Default settings for SQL instances
    disk_autoresize       = false
    disk_size             = 16   # GB
    disk_type             = "PD_SSD"
      
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
      name     = "app_user"
      # Password will be randomly generated
      host     = "%"
    }
  ]
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Use database version from the default config, allow override
  database_version = try(inputs.database_version, local.default_sqlserver_settings.database_version)
  
  # Databases to create - override in specific implementations if needed
  databases = try(inputs.databases, local.default_databases)
  
  # Users to create - override in specific implementations if needed
  users = try(inputs.users, local.default_users)
  
  # Only static defaults here; environment selection is done in the consumer
  settings = merge(
    local.default_sqlserver_settings,
    try(inputs.settings, {})
  )
  
  # IP configuration defaults - override in specific implementations
  ip_configuration = try(inputs.ip_configuration, {
    ipv4_enabled        = true
    private_network     = null  # Must be provided in specific implementation
    require_ssl         = true
    allocated_ip_range  = null
    authorized_networks = []
  })
  
  # High availability settings (should be overridden in consumer if needed)
  deletion_protection = try(inputs.deletion_protection, false)
  
  # Enable insights for monitoring performance
  insights_config = try(inputs.insights_config, {
    query_insights_enabled  = true
    query_string_length     = 1024
    record_application_tags = true
    record_client_address   = true
  })
  
  # Default SQL Server labels
  user_labels = try(inputs.user_labels, {
    managed_by  = "terragrunt"
    component   = "sqlserver"
    environment = try(inputs.environment_type, "non-production")
  })
}
