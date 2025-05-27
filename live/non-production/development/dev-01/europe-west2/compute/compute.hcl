# Common compute configuration for all VMs in this region

locals {
  # Common dependencies that all compute instances need
  common_dependencies = {
    vpc_network_path = "../../../vpc-network"
    project_path     = "../../../project"
    secrets_path     = "../../../secrets"
  }

  # Common mock outputs for dependencies
  common_mock_outputs = {
    vpc_network = {
      network_name       = "default"
      network_self_link  = "projects/mock-project/global/networks/default"
      subnets_self_links = ["projects/mock-project/regions/europe-west2/subnetworks/default"]
    }
    project = {
      # Core project outputs from terraform-google-project-factory
      project_id     = "org-test-dev"
      project_name   = "org-test-dev"
      project_number = "123456789012"
      domain         = "example.com"

      # Service account outputs
      service_account_email        = "mock-sa@mock-project-id.iam.gserviceaccount.com"
      service_account_display_name = "Compute Engine default service account"
      service_account_id           = "mock-sa@mock-project-id.iam.gserviceaccount.com"
      service_account_name         = "projects/mock-project-id/serviceAccounts/mock-sa@mock-project-id.iam.gserviceaccount.com"
      service_account_unique_id    = "123456789012345678901"

      # API service account outputs
      api_s_account     = "mock-api-sa@mock-project-id.iam.gserviceaccount.com"
      api_s_account_fmt = "serviceAccount:mock-api-sa@mock-project-id.iam.gserviceaccount.com"

      # Enabled APIs
      enabled_apis           = ["compute.googleapis.com", "storage.googleapis.com"]
      enabled_api_identities = {}

      # Storage outputs
      project_bucket_self_link = "gs://mock-project-id-bucket"
      project_bucket_url       = "gs://mock-project-id-bucket"

      # Budget outputs
      budget_name = "mock-budget"

      # Group outputs
      group_email = "mock-group@example.com"

      # Tag outputs
      tag_bindings = {}

      # Usage report outputs
      usage_report_export_bucket = "gs://mock-usage-bucket"

      # Google Cloud zones output (for compute instances)
      zones           = ["europe-west2-a", "europe-west2-b", "europe-west2-c"]
      available_zones = ["europe-west2-a", "europe-west2-b", "europe-west2-c"]
    }
    secrets = {
      secret_names = ["example-secret", "api-key-secret", "db-connection-secret"]
    }
  }

  # Common network configuration for all VMs
  common_network_config = {
    # All VMs use the first subnet by default
    subnet_index = 0
    # Default access configuration
    access_config = {
      nat_ip = null
    }
  }

  # Common service account configuration
  common_service_account_config = {
    # Default scopes for all VMs
    default_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  # Common metadata settings
  common_metadata = {
    enable-oslogin = "TRUE"
  }

  # Common labels that apply to all compute instances
  common_compute_labels = {
    component  = "compute"
    managed_by = "terragrunt"
  }

  # Common settings for all VMs
  common_vm_settings = {
    allow_stopping_for_update = true
    attached_disks            = []
  }

  # Zone mapping for different VM types (can be overridden per VM)
  zone_mapping = {
    default    = "a" # Most VMs use zone a
    worker     = "b" # Worker VMs use zone b
    db         = "c" # Database VMs use zone c
    sql_server = "b" # SQL Server VMs use zone b
  }
}
