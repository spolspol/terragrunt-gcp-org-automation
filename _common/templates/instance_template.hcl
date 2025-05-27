# Instance Template
# This template provides standardized configuration for Google Cloud instance templates
# Include this template in your Terragrunt configurations for consistent instance template setups
# Uses terraform-google-vm module's instance_template submodule

# Provider configuration is now handled centrally in root.hcl
# No local provider generation needed

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-vm.git//modules/instance_template?ref=${local.module_versions.vm}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Default instance template configuration
  default_template_config = {
    machine_type      = "e2-micro"
    disk_size_gb      = 10
    disk_type         = "pd-standard"
    auto_delete       = true
    preemptible       = true
    automatic_restart = true
    min_cpu_platform  = null

    # Network defaults
    network_tier = "STANDARD"

    # Default access scopes
    default_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]

    # Default network tags
    tags = ["terragrunt-managed"]
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  project_id  = null # Must be provided in the child module
  name_prefix = null # Must be provided in the child module
  region      = null # Must be provided in the child module

  # Machine type - will be overridden by environment-specific settings
  machine_type = local.default_template_config.machine_type

  # Network settings - override in specific implementations
  network    = null # Must be provided in child module
  subnetwork = null # Must be provided in child module

  # External IP configuration
  can_ip_forward = false

  # Boot disk configuration
  auto_delete = local.default_template_config.auto_delete

  # Instance scheduling
  preemptible       = local.default_template_config.preemptible
  automatic_restart = local.default_template_config.automatic_restart

  # Service account settings - set to null to allow service account creation
  # If create_service_account is true, this must be null for the module to create it
  service_account = null

  # Labels to apply to instances created from this template
  labels = {
    managed_by  = "terragrunt"
    component   = "compute"
    environment = "non-production"
  }

  # Metadata that applies to instances created from this template
  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "false"
  }

  # Instance tags
  tags = local.default_template_config.tags

  # Minimum CPU platform
  min_cpu_platform = local.default_template_config.min_cpu_platform

  # Additional disks configuration - defaults to empty list
  additional_disks = []

  # Startup script (optional)
  startup_script = null

  # GPU configuration (optional)
  gpu = null

  # Shielded instance configuration
  enable_shielded_vm = false
  shielded_instance_config = {
    enable_secure_boot          = false
    enable_vtpm                 = false
    enable_integrity_monitoring = false
  }

  # Access configuration for external IP
  access_config = [{
    nat_ip       = null
    network_tier = local.default_template_config.network_tier
  }]
}
