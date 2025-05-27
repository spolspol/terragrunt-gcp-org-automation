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

include "gke_template" {
  path = "${get_repo_root()}/_common/templates/gke.hcl"
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

  # Cluster naming with new pattern: {project}-{region:0:3}-{cluster-id}
  cluster_id = basename(get_terragrunt_dir()) # cluster-01
  # Generic region abbreviation: first letter of first segment + first letter of second segment + last character of second segment
  region_parts = split("-", local.merged_vars.region)
  region_abbr  = "${substr(local.region_parts[0], 0, 1)}${substr(local.region_parts[1], 0, 1)}${substr(local.region_parts[1], -1, 1)}"
}

dependency "vpc-network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name       = "mock-network"
    network_self_link  = "projects/mock-project/global/networks/mock-network"
    subnets_self_links = ["projects/mock-project/regions/europe-west2/subnetworks/mock-subnet"]
    subnets_names      = ["mock-subnet"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id            = "mock-project-id"
    project_name          = "mock-project"
    service_account_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

# Note: NAT Gateway dependencies are commented out as they need to be created separately
# dependency "nat-gateway-ip" {
#   config_path = "../../networking/external-ips/nat-gateway"
#   mock_outputs = {
#     addresses = ["mock-nat-ip"]
#   }
#   mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
#   skip_outputs                            = false
# }

# dependency "nat-gateway-firewall" {
#   config_path = "../../networking/firewall-rules/nat-gateway"
#   mock_outputs = {
#     firewall_rules = ["mock-firewall-rule"]
#   }
#   mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
#   skip_outputs                            = false
# }

# dependency "cloud-nat" {
#   config_path = "../../networking/cloud-nat"
#   mock_outputs = {
#     nat_gateway_name = "mock-nat-gateway"
#   }
#   mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
#   skip_outputs                            = false
# }

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/gke.hcl").inputs,
  local.merged_vars,
  {
    # MINIMAL GKE CONFIGURATION
    # This configuration uses the minimum set of GKE features for basic Kubernetes functionality
    # Advanced features, monitoring, security, and performance optimizations are disabled

    # Required parameters
    project_id = dependency.project.outputs.project_id
    name       = "${dependency.project.outputs.project_name}-${local.region_abbr}-${local.cluster_id}"
    region     = local.merged_vars.region
    zones      = ["${local.merged_vars.region}-a", "${local.merged_vars.region}-b", "${local.merged_vars.region}-c"]
    network    = dependency.vpc-network.outputs.network_name
    subnetwork = dependency.vpc-network.outputs.subnets_names[0]

    # Secondary ranges for pods and services
    # Note: These ranges need to be configured in the VPC network
    ip_range_pods     = "cluster-01-pods"
    ip_range_services = "cluster-01-services"

    # Environment-specific configuration
    # environment_type is internal only, not passed to module

    # Dev environment specific settings
    kubernetes_version = "latest" # Use latest in dev
    release_channel    = "REGULAR"

    # Security settings for dev
    enable_private_endpoint = false # Allow external access in dev
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.32/28" # Different from default to avoid conflicts

    # Temporarily disable deletion protection to allow destroy
    deletion_protection = false

    # Service account configuration
    create_service_account = true
    service_account_name   = "${dependency.project.outputs.project_name}-${local.cluster_id}-gke-nodes"

    # Minimal GKE features for dev - disable all non-essential features
    dns_cache                = false # Disabled for minimal setup
    enable_l4_ilb_subsetting = false # Disabled for minimal setup
    enable_cost_allocation   = false # Disabled for minimal setup
    gke_backup_agent_config  = false # Disabled for minimal setup

    # Security features - minimal set
    enable_shielded_nodes       = false # Disabled for minimal setup
    enable_binary_authorization = false # Disabled for minimal setup
    network_policy              = false # Disabled for minimal setup

    # Advanced networking - all disabled for minimal setup
    enable_fqdn_network_policy               = false
    enable_cilium_clusterwide_network_policy = false
    enable_gcfs                              = false

    # Monitoring and logging - minimal set
    monitoring_enable_managed_prometheus = false
    monitoring_enabled_components        = ["SYSTEM_COMPONENTS"]
    logging_enabled_components           = ["SYSTEM_COMPONENTS"]

    # Master authorized networks - example IPs from architecture diagram
    master_authorized_networks = [
      {
        cidr_block   = "10.0.0.0/24"
        display_name = "office-network"
      },
      {
        cidr_block   = "192.168.1.0/24"
        display_name = "vpn-range"
      },
      {
        cidr_block   = "172.16.0.0/16"
        display_name = "private-network"
      },
      {
        cidr_block   = "203.0.113.0/24"
        display_name = "public-range"
      }
    ]

    # Node pools configuration for dev (updated for v37.0.0)
    node_pools = [
      {
        name               = "workers-pool-00"
        initial_node_count = 0
        machine_type       = "n2d-highcpu-2"
        disk_size_gb       = 50
        disk_type          = "pd-standard"
        preemptible        = false
        spot               = true # Use spot instances for cost savings
        auto_repair        = true
        auto_upgrade       = true
        # service_account is omitted - will use the cluster's created service account
        enable_gvnic       = false
        enable_fast_socket = false
        # Autoscaling configuration with total limits
        autoscaling     = true
        location_policy = "ANY" # Prioritize unused reservations
        total_min_count = 0
        total_max_count = 3
      }
    ]

    # Daily maintenance window configuration (1AM UTC daily, 4-hour window)
    maintenance_start_time = "01:00"

    # Workload Identity configuration
    identity_namespace = "${dependency.project.outputs.project_id}.svc.id.goog"

    # Labels
    cluster_resource_labels = merge(
      {
        managed_by   = "terragrunt"
        component    = "gke"
        environment  = local.merged_vars.environment
        cluster_name = local.cluster_id
        gke_version  = "v37"
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )

    # Node pools labels
    node_pools_labels = {
      all = merge(
        {
          managed_by  = "terragrunt"
          component   = "gke"
          environment = local.merged_vars.environment
        },
        try(local.merged_vars.org_labels, {}),
        try(local.merged_vars.env_labels, {})
      )
    }

    # Node pools tags
    node_pools_tags = {
      all = ["gke-node", "nat-enabled", "terragrunt-managed", local.merged_vars.environment]
    }
  }
)