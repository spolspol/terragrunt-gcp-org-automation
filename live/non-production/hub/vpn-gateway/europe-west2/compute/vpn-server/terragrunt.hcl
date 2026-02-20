include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "instance_template" {
  path           = "${get_repo_root()}/_common/templates/instance_template.hcl"
  merge_strategy = "deep"
}

include "compute_common" {
  path   = find_in_parent_folders("compute.hcl")
  expose = true
}

locals {
  instance_name       = basename(get_terragrunt_dir())
  selected_env_config = lookup(include.compute_common.locals.compute_vpn_settings, "vpn", {})

  auth_type = "simple"

  dns_bind_address_default   = try(include.compute_common.locals.vpn_dns_settings.bind_address, "10.11.2.10")
  dns_forward_domain_default = try(include.compute_common.locals.vpn_dns_settings.forward_domain, "example.io")

  startup_script = local.auth_type == "simple" ? "vpn-install-enhanced.sh" : "vpn-install-sso-enhanced.sh"

  filtered_env_config = {
    machine_type        = try(local.selected_env_config.machine_type, null)
    disk_size_gb        = try(local.selected_env_config.disk_size_gb, null)
    disk_type           = try(local.selected_env_config.disk_type, null)
    preemptible         = try(local.selected_env_config.preemptible, null)
    automatic_restart   = try(local.selected_env_config.automatic_restart, null)
    min_cpu_platform    = try(local.selected_env_config.min_cpu_platform, null)
    tags                = try(local.selected_env_config.tags, null)
    auto_delete         = false
    deletion_protection = try(local.selected_env_config.deletion_protection, null)
    network_tier        = try(local.selected_env_config.network_tier, null)
    enable_display      = try(local.selected_env_config.enable_display, null)
    boot_disk           = try(local.selected_env_config.boot_disk, null)
    service_account = try(local.selected_env_config.scopes, null) != null ? {
      email  = null
      scopes = local.selected_env_config.scopes
    } : null
  }
}

dependency "vpc_network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name       = "org-vpn-gateway-vpc"
    network_self_link  = "projects/org-vpn-gateway/global/networks/org-vpn-gateway-vpc"
    subnets_self_links = ["projects/org-vpn-gateway/regions/europe-west2/subnetworks/vpn-server-subnet"]
    subnets_names      = ["vpn-server-subnet"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "vpn_server_sa" {
  config_path = "../../../iam-service-accounts/vpn-server"
  mock_outputs = {
    email = "vpn-server@org-vpn-gateway.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "private_ip" {
  config_path = "../../networking/internal-ips/vpn-server"
  mock_outputs = {
    addresses = ["10.11.2.10"]
    names     = ["org-vpn-gateway-vpn-server"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "vm_scripts" {
  config_path = "../../buckets/vm-scripts"
  mock_outputs = {
    name = "org-vpn-gateway-vm-scripts"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "admin_password_secret" {
  config_path  = "../../../secrets/vpn-admin-password"
  skip_outputs = !fileexists("${get_terragrunt_dir()}/../../../secrets/vpn-admin-password/terragrunt.hcl")
  mock_outputs = {
    secret_id = "vpn-admin-password"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = merge(
  local.filtered_env_config,
  {
    project_id  = try(dependency.project.outputs.project_id, "org-vpn-gateway")
    name_prefix = "${basename(get_terragrunt_dir())}"
    region      = include.base.locals.region

    network = try(
      dependency.vpc_network.outputs.network_self_link,
      format(
        "projects/%s/global/networks/org-vpn-gateway-vpc",
        try(dependency.project.outputs.project_id, "org-vpn-gateway")
      )
    )
    subnetwork = try(
      element([
        for subnet in try(dependency.vpc_network.outputs.subnets, []) : subnet.self_link
        if try(subnet.name, "") == "vpn-server-subnet"
      ], 0),
      format(
        "projects/%s/regions/%s/subnetworks/vpn-server-subnet",
        try(dependency.project.outputs.project_id, "org-vpn-gateway"),
        include.base.locals.region
      )
    )
    subnetwork_project = try(dependency.project.outputs.project_id, "org-vpn-gateway")
    network_ip         = try(dependency.private_ip.outputs.addresses[0], "10.11.2.10")

    source_image         = "ubuntu-2404-noble-amd64-v20251021"
    source_image_family  = "ubuntu-2404-lts-amd64"
    source_image_project = "ubuntu-os-cloud"

    metadata = merge(
      include.compute_common.locals.common_metadata,
      {
        startup-script-url    = "gs://${try(dependency.vm_scripts.outputs.name, "org-vpn-gateway-vm-scripts")}/vpn-server/${local.startup_script}"
        auth-type             = local.auth_type
        admin-password-secret = try(dependency.admin_password_secret.outputs.secret_id, "")
        dns-bind-address      = try(dependency.private_ip.outputs.addresses[0], local.dns_bind_address_default)
        dns-forward-domain    = local.dns_forward_domain_default
      }
    )

    service_account = {
      email  = dependency.vpn_server_sa.outputs.email
      scopes = try(local.selected_env_config.scopes, ["https://www.googleapis.com/auth/cloud-platform"])
    }

    labels = merge(
      include.compute_common.locals.common_compute_labels,
      {
        type      = "vpn-server"
        auth_type = local.auth_type
        component = "vpn"
      }
    )

    enable_shielded_vm       = include.compute_common.locals.common_vm_settings.enable_shielded_vm
    shielded_instance_config = include.compute_common.locals.common_vm_settings.shielded_instance_config

    access_config = [{ nat_ip = null, network_tier = "STANDARD" }]

    create_service_account = false
  }
)
