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
  path = find_in_parent_folders("_common/common.hcl")
}

include "compute_template" {
  path = find_in_parent_folders("_common/templates/compute_instance.hcl")
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
  common_vars  = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))

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

  # Filter env config to only include variables supported by compute_instance module
  filtered_env_config = {
    deletion_protection = try(local.selected_env_config.deletion_protection, null)
    network_tier        = try(local.selected_env_config.network_tier, null)
  }
}

dependency "instance_template" {
  config_path = "../"
  mock_outputs = {
    self_link = "projects/mock-project/global/instanceTemplates/mock-template"
    name      = "mock-template"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "vpc-network" {
  config_path = "../../../../vpc-network"
  mock_outputs = {
    network_name       = "default"
    network_self_link  = "projects/mock-project/global/networks/default"
    subnets_self_links = ["projects/mock-project/regions/europe-west2/subnetworks/default"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id            = "org-test-dev"
    service_account_email = "mock-sa@mock-project-id.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

# Dependency on the external IP reserved for SQL Server
dependency "external_ip" {
  config_path = "../../../external-ips/sql-server"
  mock_outputs = {
    addresses = ["203.0.113.1"]
    names     = ["mock-external-ip"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = merge(
  local.filtered_env_config,
  {
    # Required basic instance configuration - accepted by compute_instance module
    hostname = "${try(dependency.project.outputs.project_name, "mock-project-name")}-${basename(dirname(get_terragrunt_dir()))}"
    zone     = "${local.merged_vars.region}-${local.merged_vars.zone_mapping.sql_server}"
    region   = local.merged_vars.region

    # Instance template dependency - compute_instance module uses this template
    instance_template = try(dependency.instance_template.outputs.self_link, "projects/mock-project/global/instanceTemplates/mock-template")

    # Network configuration - accepted by compute_instance module
    network            = try(dependency.vpc-network.outputs.network_self_link, "projects/mock-project/global/networks/default")
    subnetwork         = try(dependency.vpc-network.outputs.subnets_self_links[0], "projects/mock-project/regions/europe-west2/subnetworks/default")
    subnetwork_project = try(dependency.project.outputs.project_id, "mock-project-id")

    # External IP configuration - accepted by compute_instance module
    access_config = [{
      nat_ip       = try(dependency.external_ip.outputs.addresses[0], null)
      network_tier = try(local.filtered_env_config.network_tier, "STANDARD")
    }]

    # Resource Labels - accepted by compute_instance module
    labels = merge(
      {
        managed_by  = "terragrunt"
        component   = "compute"
        environment = local.merged_vars.environment
      },
      {
        instance         = "sql-server-01"
        purpose          = "database"
        database_type    = "mssql"
        database_version = "2022-web"
        os_type          = "windows"
        environment_type = local.merged_vars.environment_type
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )

    # Additional configuration - accepted by compute_instance module
    deletion_protection = try(local.filtered_env_config.deletion_protection, true)

    # Number of instances to create - accepted by compute_instance module
    num_instances = 1

    # Static IPs - accepted by compute_instance module
    static_ips = []
  }
)
