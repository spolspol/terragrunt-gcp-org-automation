# ArgoCD Bootstrap Configuration
# This configuration deploys ArgoCD GitOps platform to the GKE cluster

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

  # Assembled values for ArgoCD module from path and configuration
  gcp_folder = local.merged_vars.environment           # "development"
  gcp_region = local.merged_vars.region                # "europe-west2"
  cluster_id = basename(dirname(get_terragrunt_dir())) # "cluster-01"
  
  # Dynamic path construction for secrets
  # Navigate up to project level then down to secrets
  project_base_path = dirname(dirname(dirname(dirname(get_terragrunt_dir()))))
  secrets_base_path = "${local.project_base_path}/secrets"
  
  # Dynamic path construction for networking resources
  region_base_path = dirname(dirname(dirname(get_terragrunt_dir())))
  networking_base_path = "${local.region_base_path}/networking"
}

# Dependencies
dependency "gke_cluster" {
  config_path = "../"
  mock_outputs = {
    name            = "dev-01-ew2-cluster-01"
    endpoint        = "1.2.3.4"
    ca_certificate  = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
    service_account = "dev-01-cluster-01-gke-nodes@dev-01.iam.gserviceaccount.com"
    cluster_id      = "dev-01-ew2-cluster-01"
    location        = "europe-west2"
    master_version  = "1.28.3-gke.1286000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = find_in_parent_folders("project")
  mock_outputs = {
    project_id            = "mock-project-id"
    project_name          = "mock-project"
    service_account_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

# Secret dependencies using dynamic paths
dependency "argocd_oauth_secret" {
  config_path = "${local.secrets_base_path}/gke-argocd-oauth-client-secret"
  mock_outputs = {
    secret_id           = "gke-argocd-oauth-client-secret"
    secret_version_data = "mock-secret-data" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "grafana_oauth_id" {
  config_path = "${local.secrets_base_path}/gke-grafana-oauth-client-id"
  mock_outputs = {
    secret_id           = "gke-grafana-oauth-client-id"
    secret_version_data = "mock-client-id" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "grafana_oauth_secret" {
  config_path = "${local.secrets_base_path}/gke-grafana-oauth-client-secret"
  mock_outputs = {
    secret_id           = "gke-grafana-oauth-client-secret"
    secret_version_data = "mock-secret-data" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "github_pat" {
  config_path = "${local.secrets_base_path}/gke-github-runners-personal-access-token"
  mock_outputs = {
    secret_id           = "gke-github-runners-personal-access-token"
    secret_version_data = "mock-pat" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "alertmanager_webhooks" {
  config_path = "${local.secrets_base_path}/gke-alertmanager-webhook-urls"
  mock_outputs = {
    secret_id           = "gke-alertmanager-webhook-urls"
    secret_version_data = "{}" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "argocd_slack_webhook" {
  config_path = "${local.secrets_base_path}/gke-argocd-slack-webhook"
  mock_outputs = {
    secret_id           = "gke-argocd-slack-webhook"
    secret_version_data = "https://hooks.slack.com/services/mock" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "k8s_slack_webhook" {
  config_path = "${local.secrets_base_path}/gke-k8s-slack-webhook"
  mock_outputs = {
    secret_id           = "gke-k8s-slack-webhook"
    secret_version_data = "https://hooks.slack.com/services/mock" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "argocd_dex_service_account" {
  config_path = "${local.secrets_base_path}/gke-argocd-dex-service-account"
  mock_outputs = {
    secret_id           = "gke-argocd-dex-service-account"
    secret_version_data = "eyJtb2NrIjogInNlcnZpY2UtYWNjb3VudCJ9" # pragma: allowlist secret
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true # Skip if secret doesn't exist yet
}

dependency "services-ip" {
  config_path = "${local.networking_base_path}/external-ips/${local.cluster_id}-services"
  mock_outputs = {
    addresses = ["35.246.0.123"] # Mock IP for hex conversion example
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

terraform {
  # Use remote Git reference - main branch for now, will create versioned tags
  source = "git::https://github.com/your-org/gke-argocd-cluster-gitops.git//terraform/modules/argocd?ref=main"
  
  # TODO: Switch to versioned reference once tags are created:
  # source = "git::https://github.com/your-org/gke-argocd-cluster-gitops.git//terraform/modules/argocd?ref=${local.merged_vars.module_versions.argocd}"
}

# Provider configuration for Kubernetes and Helm
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# Data source for Google client config (for access token)
data "google_client_config" "default" {}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = "https://${dependency.gke_cluster.outputs.endpoint}"
  cluster_ca_certificate = base64decode("${dependency.gke_cluster.outputs.ca_certificate}")
  token                  = data.google_client_config.default.access_token
}

# Helm provider configuration
provider "helm" {
  kubernetes = {
    host                   = "https://${dependency.gke_cluster.outputs.endpoint}"
    cluster_ca_certificate = base64decode("${dependency.gke_cluster.outputs.ca_certificate}")
    token                  = data.google_client_config.default.access_token
  }
}
EOF
}

inputs = {
  # === SECRET DEPENDENCIES NOTE ===
  # The following secrets should be created before deploying the full GitOps stack:
  # - gke-argocd-oauth-client-secret: OAuth secret for ArgoCD (managed via External Secrets)
  # - gke-grafana-oauth-client-id: OAuth client ID for Grafana
  # - gke-grafana-oauth-client-secret: OAuth secret for Grafana authentication
  # - gke-github-runners-personal-access-token: PAT for GitHub self-hosted runners
  # - gke-alertmanager-webhook-urls: Webhook URLs for Alertmanager notifications
  # - gke-argocd-slack-webhook: Slack webhook URL for ArgoCD notifications
  # - gke-k8s-slack-webhook: Slack webhook URL for Kubernetes alerts
  # - gke-argocd-dex-service-account: Google service account key for Dex OAuth
  #
  # Note: These secrets are consumed by GitOps applications via External Secrets Operator,
  # not directly by this Terraform module. The dependencies above ensure proper deployment order.

  # === CORE CLUSTER IDENTITY (REQUIRED) ===
  cluster_name   = dependency.gke_cluster.outputs.name
  environment    = local.gcp_folder
  gcp_folder     = local.gcp_folder
  gcp_project_id = dependency.project.outputs.project_id
  gcp_region     = local.gcp_region

  # === MINIMAL ARGOCD BOOTSTRAP CONFIGURATION ===
  namespace_name       = "argocd"
  argocd_chart_version = "8.1.3"

  # === BOOTSTRAP REPOSITORY ===
  bootstrap_repo_url      = "https://github.com/your-org/gke-argocd-cluster-gitops"
  bootstrap_repo_revision = "main" # Use stable version for production reliability

  # === CLUSTER DOMAIN CONFIGURATION ===
  # Domain constructed from external IP: 123.123.123.123 -> 7b7b7b7b.sslip.io
  # IP to hex conversion performed inline
  cluster_domain = format("%s.sslip.io", join("", [
    format("%02x", tonumber(split(".", dependency.services-ip.outputs.addresses[0])[0])),
    format("%02x", tonumber(split(".", dependency.services-ip.outputs.addresses[0])[1])),
    format("%02x", tonumber(split(".", dependency.services-ip.outputs.addresses[0])[2])),
    format("%02x", tonumber(split(".", dependency.services-ip.outputs.addresses[0])[3]))
  ]))

  # === INGRESS CONFIGURATION ===
  # Reserved external IP for the cluster's ingress controller
  ingress_reserved_ip = dependency.services-ip.outputs.addresses[0]

  # === GITHUB AUTHENTICATION (OPTIONAL) === #pragma: allowlist secret
  # For private repository access during bootstrap
  # Set via environment variable: export GITHUB_TOKEN="your-github-pat"
  github_token = get_env("GITHUB_TOKEN", "")

  # === SERVICE ACCOUNT CONFIGURATION ===
  # These control which GCP service accounts are created
  enable_oauth_groups_sa             = false # Groups IAM not needed
  enable_grafana_oauth_token_manager = true  # Keep Grafana OAuth token manager enabled
}