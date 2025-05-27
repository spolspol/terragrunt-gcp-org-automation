# Compute Instance Template
# This template provides standardized configuration for Google Cloud compute instances
# Include this template in your Terragrunt configurations for consistent VM setups
# Uses terraform-google-vm module's compute_instance submodule

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-vm.git//modules/compute_instance?ref=${local.module_versions.vm}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Default instance configuration
  default_instance_config = {
    machine_type        = "e2-micro"
    disk_size_gb        = 10
    disk_type           = "pd-standard"
    auto_delete         = true
    preemptible         = false
    automatic_restart   = true
    min_cpu_platform    = null
    enable_display      = false
    deletion_protection = false

    # Network defaults
    network_tier = "STANDARD"
    subnet       = "default"

    # Default access scopes if no service account provided
    default_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]

    # Default network tags
    tags = ["terragrunt-managed"]

    # Default OS
    image_family  = "debian-12"
    image_project = "debian-cloud"
  }

  # Environment-specific settings
  env_instance_configs = {
    production = {
      machine_type        = "e2-standard-2"
      disk_size_gb        = 50
      disk_type           = "pd-ssd"
      preemptible         = false
      automatic_restart   = true
      deletion_protection = true
      min_cpu_platform    = "Intel Cascade Lake"
      network_tier        = "PREMIUM"

      # Monitoring settings
      monitoring = {
        enabled       = true
        logging_level = "FULL"
      }
    },
    non-production = {
      machine_type        = "e2-small"
      disk_size_gb        = 20
      disk_type           = "pd-standard"
      preemptible         = true
      automatic_restart   = false
      deletion_protection = false

      # Monitoring settings
      monitoring = {
        enabled       = true
        logging_level = "BASIC"
      }
    }
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  project_id = null # Will be provided by dependency in child module
  hostname   = null # Must be provided in the child module
  zone       = null # Must be provided in the child module
  # Region of the instance (used by modules that require it)
  region = null # Must be provided in the child module

  # Instance template dependency - must be provided
  instance_template = null # Must be provided in the child module

  # Machine type - will be overridden by environment-specific settings
  machine_type = local.default_instance_config.machine_type

  # Network settings - will be provided by dependency in child module
  network            = null # Will be provided by dependency in child module
  subnetwork         = null # Will be provided by dependency in child module
  subnetwork_project = null # Will be provided by dependency in child module

  # External IP configuration
  access_config = [{
    nat_ip       = null
    network_tier = local.default_instance_config.network_tier
  }]

  # Boot disk configuration
  source_image = "${local.default_instance_config.image_project}/${local.default_instance_config.image_family}"
  disk_size_gb = local.default_instance_config.disk_size_gb
  disk_type    = local.default_instance_config.disk_type
  auto_delete  = local.default_instance_config.auto_delete

  # Instance scheduling
  preemptible       = local.default_instance_config.preemptible
  automatic_restart = local.default_instance_config.automatic_restart

  # Service account settings - will be provided by dependency in child module
  service_account = {
    email  = null # Will be provided by dependency in child module
    scopes = local.default_instance_config.default_scopes
  }

  # Labels to apply to the instance
  labels = {
    managed_by  = "terragrunt"
    component   = "compute"
    environment = "non-production"
  }

  # Metadata that applies to the instance
  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "false"
  }

  # Instance tags
  tags = local.default_instance_config.tags

  # Deletion protection based on environment
  deletion_protection = local.default_instance_config.deletion_protection

  # Enable display for serial console access
  enable_display = local.default_instance_config.enable_display

  # Minimum CPU platform
  min_cpu_platform = local.default_instance_config.min_cpu_platform

  # Allow IP forwarding
  can_ip_forward = false

  # Attached disk configuration - defaults to empty list
  additional_disks = []

  # Additional networks (empty by default)
  additional_networks = []

  # Startup script (optional)
  startup_script = null

  # Number of instances to create (for compute_instance module)
  num_instances = 1

  # Static IPs (optional)
  static_ips = []

  # GPU configuration (optional)
  gpu = null

  # Shielded instance configuration
  enable_shielded_vm = false
  shielded_instance_config = {
    enable_secure_boot          = false
    enable_vtpm                 = false
    enable_integrity_monitoring = false
  }
}
