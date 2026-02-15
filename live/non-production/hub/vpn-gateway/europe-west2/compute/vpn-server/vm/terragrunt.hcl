include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "compute_template" {
  path           = "${get_repo_root()}/_common/templates/compute_instance.hcl"
  merge_strategy = "deep"
}

include "compute_common" {
  path   = find_in_parent_folders("compute.hcl")
  expose = true
}

locals {
  selected_env_config = lookup(include.base.locals.merged.compute_instance_settings, include.base.locals.environment, {})

  filtered_env_config = {
    deletion_protection = try(local.selected_env_config.deletion_protection, null)
    network_tier        = try(local.selected_env_config.network_tier, null)
  }

  instance_basename = basename(dirname(get_terragrunt_dir()))
}

dependency "instance_template" {
  config_path = "../"
  mock_outputs = {
    self_link = "projects/org-vpn-gateway/global/instanceTemplates/mock-template"
    name      = "mock-template"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "vpc-network" {
  config_path = "../../../../vpc-network"
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
  config_path = "../../../../project"
  mock_outputs = {
    project_id            = "org-vpn-gateway"
    service_account_email = "mock-sa@org-vpn-gateway.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "external_ip" {
  config_path = "../../../networking/external-ips/vpn-server"
  mock_outputs = {
    addresses = ["35.214.48.26"]
    names     = ["org-vpn-gateway-vpn-server"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "private_ip" {
  config_path = "../../../networking/internal-ips/vpn-server"
  mock_outputs = {
    addresses = ["10.11.2.10"]
    names     = ["org-vpn-gateway-vpn-server"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = merge(
  local.filtered_env_config,
  {
    project_id = try(dependency.project.outputs.project_id, "org-vpn-gateway")
    region     = include.base.locals.region
    zone       = "${include.base.locals.region}-${try(include.compute_common.locals.zone_mapping.vpn, "a")}"

    network = try(
      dependency.vpc-network.outputs.network_self_link,
      format(
        "projects/%s/global/networks/org-vpn-gateway-vpc",
        try(dependency.project.outputs.project_id, "org-vpn-gateway")
      )
    )
    subnetwork = try(
      element([
        for subnet in try(dependency.vpc-network.outputs.subnets, []) : subnet.self_link
        if try(subnet.name, "") == "vpn-server-subnet"
      ], 0),
      format(
        "projects/%s/regions/%s/subnetworks/vpn-server-subnet",
        try(dependency.project.outputs.project_id, "org-vpn-gateway"),
        include.base.locals.region
      )
    )
    subnetwork_project = try(dependency.project.outputs.project_id, "org-vpn-gateway")

    instance_template = try(dependency.instance_template.outputs.self_link, null)
    hostname          = local.instance_basename

    num_instances = 1

    access_config = [{
      nat_ip       = try(dependency.external_ip.outputs.addresses[0], null)
      network_tier = "STANDARD"
    }]

    static_ips = [try(dependency.private_ip.outputs.addresses[0], "10.11.2.10")]

    labels = merge(
      include.compute_common.locals.common_compute_labels,
      {
        instance  = "primary"
        hostname  = local.instance_basename
        type      = "vpn-server"
        component = "vpn"
      }
    )
  }
)
