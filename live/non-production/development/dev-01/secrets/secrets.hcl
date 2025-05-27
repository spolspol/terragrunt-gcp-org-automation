# Shared configuration for all secrets in this project
# This file contains common settings for Secret Manager resources

locals {
  # Common secret configuration
  secret_config = {
    # Replication policy for secrets
    replication_policy = "automatic"
    
    # Default labels for all secrets
    default_labels = {
      component = "web-server"
      managed_by = "terragrunt"
    }
    
    # Rotation settings (if needed)
    rotation_period = null  # Set to "86400s" for daily rotation if needed
  }
  
  # List of secrets that should be created
  # This helps with documentation and validation
  expected_secrets = [
    "ssl-cert-email",     # Email for Let's Encrypt SSL certificates
    "ssl-domains",        # Comma-separated list of domains for SSL
  ]
}