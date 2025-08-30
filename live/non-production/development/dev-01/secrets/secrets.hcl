# Common secrets configuration for all secrets in this environment

locals {
  # Common dependencies that all secrets need
  common_dependencies = {
    project_path = find_in_parent_folders("project")
  }

  # Common mock outputs for dependencies
  common_mock_outputs = {
    project = {
      project_id            = "mock-project-id"
      service_account_email = "mock-sa@mock-project.iam.gserviceaccount.com"
    }
  }

  # Common secret configuration
  secret_config = {
    # Replication policy for secrets
    replication_policy = "automatic"
    
    # Default labels for all secrets
    default_labels = {
      component  = "secret-manager"
      managed_by = "terragrunt"
    }
    
    # Rotation settings
    rotation_period = "7776000s" # 90 days
  }
  
  # Common secret settings
  common_secret_settings = {
    rotation_period = "7776000s" # 90 days
  }

  # Common IAM roles for secret access
  common_secret_roles = [
    "roles/secretmanager.secretAccessor",
    "roles/secretmanager.viewer"
  ]

  # Common labels that apply to all secrets
  common_secret_labels = {
    component  = "secret-manager"
    managed_by = "terragrunt"
  }

  # Environment-specific settings for secrets
  environment_secret_settings = {
    production = {
      deletion_protection = true
      rotation_enabled    = true
    }
    non-production = {
      deletion_protection = false
      rotation_enabled    = false
    }
  }
  
  # List of secrets that should be created
  # This helps with documentation and validation
  expected_secrets = [
    "ssl-cert-email",                          # Email for Let's Encrypt SSL certificates
    "ssl-domains",                             # Comma-separated list of domains for SSL
    "app-secret",                              # Application secret
    "gke-argocd-oauth-client-secret",         # ArgoCD OAuth secret
    "gke-alertmanager-webhook-urls",          # Alertmanager webhooks
    "gke-argocd-dex-service-account",         # Dex service account
    "gke-argocd-slack-webhook",               # ArgoCD Slack webhook
    "gke-grafana-oauth-client-id",            # Grafana OAuth ID
    "gke-grafana-oauth-client-secret",        # Grafana OAuth secret
    "gke-github-runners-personal-access-token", # GitHub runners PAT
    "gke-k8s-slack-webhook",                  # K8s Slack webhook
    "sql-server-admin-password",              # SQL Server admin password
    "sql-server-dba-password"                 # SQL Server DBA password
  ]
}