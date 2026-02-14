locals {
  # Environment type for configuration selection
  environment                   = "hub"
  environment_type              = "infrastructure"
  environment_name              = "network-hub"
  environment_usage_bucket_name = "org-billing-usage-reports"
  env_folder                    = "hub"

  # Environment-specific naming prefix
  name_prefix = ""

  # Environment-specific labels
  env_labels = {
    environment = "hub"
    purpose     = "network-connectivity"
  }

  # Environment-specific settings
  env_settings = {
    deletion_protection = true
    auto_create_network = false
    monitoring_level    = "enhanced"
    backup_retention    = "30d"
  }
}
