# Cloud SQL PostgreSQL Module Template
# This template provides standardized Cloud SQL PostgreSQL instance configurations
# Include this template in your Terragrunt configurations for consistent Cloud SQL PostgreSQL setups

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-sql-db.git//modules/postgresql?ref=${local.module_versions.sql_db}"

  # Add before_hook for validation if needed
  before_hook "validate_inputs" {
    commands = ["apply", "plan"]
    execute  = ["echo", "Validating Cloud SQL PostgreSQL inputs..."]
  }

  # Add after_hook for notifications or other post-deployment tasks
  after_hook "notify_completion" {
    commands = ["apply"]
    execute  = ["echo", "Cloud SQL PostgreSQL deployment completed!"]
  }
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Default Cloud SQL configuration for PostgreSQL 17
  default_cloud_sql_settings = {
    database_version = "POSTGRES_17" # Latest PostgreSQL version

    # Default settings for PostgreSQL instances
    disk_autoresize = false
    disk_size       = 10       # GB - minimum size
    disk_type       = "PD_HDD" # Cheapest disk type

    # PostgreSQL specific database flags
    database_flags = [] # Add flags as needed
  }

  # Default databases to create
  default_databases = [
    {
      name      = "main"
      charset   = "UTF8"
      collation = "en_US.UTF8"
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
# NOTE: With merge_strategy = "deep", Terragrunt appends lists instead of
# replacing them. Keep list defaults as [] and let children provide values.
inputs = {
  # Use database version from the default config, allow override
  database_version = try(inputs.database_version, local.default_cloud_sql_settings.database_version)

  # Databases to create - override in specific implementations if needed
  additional_databases = []

  # Users to create - override in specific implementations if needed
  additional_users = []

  # Set specific configuration directly based on defaults
  disk_autoresize = try(inputs.disk_autoresize, local.default_cloud_sql_settings.disk_autoresize)
  disk_size       = try(inputs.disk_size, local.default_cloud_sql_settings.disk_size)
  disk_type       = try(inputs.disk_type, local.default_cloud_sql_settings.disk_type)
  database_flags  = try(inputs.database_flags, local.default_cloud_sql_settings.database_flags)

  # IP configuration defaults - override in specific implementations
  ip_configuration = try(inputs.ip_configuration, {
    ipv4_enabled        = false # Private by default
    private_network     = null  # Must be provided in specific implementation
    require_ssl         = true
    allocated_ip_range  = null # Must be provided for PSA
    authorized_networks = []
  })

  # High availability settings (should be overridden in consumer if needed)
  deletion_protection_enabled = try(inputs.deletion_protection_enabled, false)

  # Default Cloud SQL labels for PostgreSQL
  user_labels = try(inputs.user_labels, {
    managed_by    = "terragrunt"
    component     = "cloud-sql"
    database_type = "postgresql"
    version       = "17"
    environment   = try(inputs.environment_type, "non-production")
  })
}
