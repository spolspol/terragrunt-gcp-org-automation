# Cloud Run (v2) Template
# Standardized defaults for Cloud Run services using terraform-google-cloud-run (modules/v2).

terraform {
  source = "git::https://github.com/GoogleCloudPlatform/terraform-google-cloud-run.git//modules/v2?ref=${local.module_versions.cloud_run}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  default_container = {
    # Required in service implementations
    container_image = null

    # Optional overrides
    container_args    = null
    container_command = null
    env_vars          = {}
    env_secret_vars   = {}
    volume_mounts     = []

    ports = {
      name           = "http1"
      container_port = 8080
    }

    resources = {
      limits = {
        cpu    = "1"
        memory = "512Mi"
      }
      cpu_idle          = true
      startup_cpu_boost = false
    }

    startup_probe  = null
    liveness_probe = null
  }

  default_labels = merge(
    {
      managed_by = "terragrunt"
      component  = "cloud-run"
    },
    try(local.common_vars.locals.common_tags, {})
  )
}

# NOTE: With merge_strategy = "deep", Terragrunt appends lists instead of
# replacing them. Keep list defaults as [] and let children provide values.
inputs = {
  # Required parameters - must be provided in child module
  project_id   = null
  location     = null
  service_name = null
  containers   = []

  description = null

  # Networking
  ingress    = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  vpc_access = null

  # Scaling and performance
  template_scaling = {
    min_instance_count = 0
    max_instance_count = 10
  }
  max_instance_request_concurrency = "80"
  timeout                          = "300s"

  # Identity and access
  create_service_account        = true
  service_account               = null
  service_account_project_roles = []
  members                       = []
  iap_members                   = []

  # Traffic
  traffic = []

  # Labels and annotations
  service_labels       = local.default_labels
  template_labels      = local.default_labels
  service_annotations  = {}
  template_annotations = {}

  # Security and operations
  cloud_run_deletion_protection = true
  enable_prometheus_sidecar     = false
  binary_authorization          = null
  custom_audiences              = null
  encryption_key                = null
  launch_stage                  = "GA"
  execution_environment         = "EXECUTION_ENVIRONMENT_GEN2"
  session_affinity              = null
  volumes                       = []
  node_selector                 = null
  gpu_zonal_redundancy_disabled = false

  # Optional service-level controls
  service_scaling = null
  client          = {}
}
