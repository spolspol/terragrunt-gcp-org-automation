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

include "instance_template" {
  path = "${get_repo_root()}/_common/templates/instance_template.hcl"
}

include "compute_common" {
  path = find_in_parent_folders("compute.hcl")
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  compute_vars = read_terragrunt_config(find_in_parent_folders("compute.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.compute_vars.locals,
    local.common_vars.locals
  )

  # Only use prefix if it exists and is not empty
  name_prefix         = try(local.merged_vars.name_prefix, "")
  selected_env_config = lookup(local.merged_vars.compute_instance_settings, local.merged_vars.environment_type, {})

  # Filter env config to only include variables supported by instance_template module
  filtered_env_config = {
    machine_type        = try(local.selected_env_config.machine_type, null)
    disk_size_gb        = try(local.selected_env_config.disk_size_gb, null)
    disk_type           = try(local.selected_env_config.disk_type, null)
    preemptible         = try(local.selected_env_config.preemptible, null)
    automatic_restart   = try(local.selected_env_config.automatic_restart, null)
    min_cpu_platform    = try(local.selected_env_config.min_cpu_platform, null)
    tags                = try(local.selected_env_config.tags, null)
    auto_delete         = try(local.selected_env_config.auto_delete, null)
    deletion_protection = try(local.selected_env_config.deletion_protection, null)
    network_tier        = try(local.selected_env_config.network_tier, null)
    enable_display      = try(local.selected_env_config.enable_display, null)
    boot_disk           = try(local.selected_env_config.boot_disk, null)
    # No additional disks needed for simple web server
    # Service account config - only if scopes are defined
    service_account = try(local.selected_env_config.scopes, null) != null ? {
      email  = null # Will be overridden in main config
      scopes = local.selected_env_config.scopes
    } : null
  }
}

dependency "vpc-network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name       = "default"
    network_self_link  = "projects/mock-project/global/networks/default"
    subnets_self_links = ["projects/mock-project/regions/europe-west2/subnetworks/default"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id            = "mock-project-id"
    service_account_email = "mock-sa@mock-project-id.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

# No secret dependencies needed for simple web server example

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/instance_template.hcl").inputs,
  local.filtered_env_config,
  {
    # Required instance template configuration
    project_id  = try(dependency.project.outputs.project_id, "mock-project-id")
    name_prefix = "${try(dependency.project.outputs.project_name, "mock-project-name")}-${basename(get_terragrunt_dir())}"
    region      = local.merged_vars.region

    # Network configuration
    network    = try(dependency.vpc-network.outputs.network_self_link, "projects/mock-project/global/networks/default")
    subnetwork = try(dependency.vpc-network.outputs.subnets_self_links[0], "projects/mock-project/regions/europe-west2/subnetworks/default")

    # Boot disk configuration for Debian Linux
    source_image_family  = "debian-12"
    source_image_project = "debian-cloud"
    disk_size_gb         = try(local.selected_env_config.disk_size_gb, 20)
    disk_type            = try(local.selected_env_config.disk_type, "pd-standard")
    auto_delete          = try(local.selected_env_config.auto_delete, true)

    # Instance scheduling
    preemptible       = try(local.selected_env_config.preemptible, true)
    automatic_restart = try(local.selected_env_config.automatic_restart, false)

    # Service account configuration
    service_account = {
      email = try(dependency.project.outputs.service_account_email, "mock-sa@mock-project-id.iam.gserviceaccount.com")
      scopes = try(local.selected_env_config.scopes, [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring.write",
        "https://www.googleapis.com/auth/service.management.readonly",
        "https://www.googleapis.com/auth/servicecontrol"
      ])
    }

    # Labels for instances created from this template
    labels = merge(
      {
        managed_by  = "terragrunt"
        component   = "compute"
        environment = local.merged_vars.environment
      },
      {
        instance         = "linux-web-01"
        purpose          = "web-server"
        web_server       = "nginx"
        os_type          = "linux"
        os_family        = "debian"
        environment_type = local.merged_vars.environment_type
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )

    # Metadata for instances created from this template
    metadata = {
      enable-oslogin         = "TRUE"
      block-project-ssh-keys = "false"
    }
    
    # Startup script for Linux
    startup_script = templatefile("${get_terragrunt_dir()}/startup-script.sh", {
      environment_type = local.merged_vars.environment_type
      region           = local.merged_vars.region
      machine_type     = try(local.selected_env_config.machine_type, "e2-micro")
      disk_type        = try(local.selected_env_config.disk_type, "pd-standard")
      project_id       = try(dependency.project.outputs.project_id, "mock-project-id")
    })

    # Instance tags
    tags = concat(
      try(local.selected_env_config.tags, ["terragrunt-managed"]),
      ["linux", "web-server", "nginx", "ssh", "http-server"]
    )

    # Additional configuration
    min_cpu_platform = try(local.selected_env_config.min_cpu_platform, null)
    
    # Machine type configuration
    machine_type = try(local.selected_env_config.machine_type, "e2-micro")
  }
)
