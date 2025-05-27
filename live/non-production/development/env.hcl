locals {
  # Environment type for configuration selection
  environment                   = "development"
  environment_type              = "non-production"
  environment_name              = "org-development"
  environment_usage_bucket_name = "org-billing-development-usage-reports"

  # Environment-specific naming prefix
  name_prefix = ""

  # Environment-specific labels
  env_labels = {
    environment = "development"
  }

  # Environment-specific settings
  env_settings = {
    deletion_protection = false
    auto_create_network = false
    monitoring_level    = "standard"
    backup_retention    = "7d"
  }
}
