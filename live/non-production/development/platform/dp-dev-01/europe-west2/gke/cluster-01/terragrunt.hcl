# GKE cluster for data platform workloads

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "gke_template" {
  path           = "${get_repo_root()}/_common/templates/gke.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name      = "mock-network"
    network_self_link = "projects/mock-project/global/networks/mock-network"
    subnets_names     = ["mock-network-gke"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "nat_ip" {
  config_path = "../../networking/external-ips/nat-gateway"
  mock_outputs = {
    addresses = ["0.0.0.0"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name = try(dependency.project.outputs.project_name, "dp-dev-01")
  cluster_name = "${local.project_name}-ew2-cluster-01"
}

inputs = {
  project_id = dependency.project.outputs.project_id
  name       = local.cluster_name
  region     = include.base.locals.region
  zones      = ["europe-west2-a", "europe-west2-b", "europe-west2-c"]

  network           = dependency.network.outputs.network_name
  subnetwork        = "${dependency.network.outputs.network_name}-gke"
  ip_range_pods     = "cluster-01-pods"
  ip_range_services = "cluster-01-services"

  kubernetes_version = "latest"
  release_channel    = "RAPID"

  # Private cluster configuration
  enable_private_nodes         = true
  enable_private_endpoint      = true
  master_ipv4_cidr_block       = "172.16.0.48/28"
  master_global_access_enabled = true

  # Master authorised networks
  master_authorized_networks = [
    {
      cidr_block   = "10.11.2.0/24"
      display_name = "VPN server subnet"
    },
    {
      cidr_block   = "10.11.101.0/24"
      display_name = "Admin VPN pool"
    },
    {
      cidr_block   = "${dependency.nat_ip.outputs.addresses[0]}/32"
      display_name = "NAT gateway"
    },
  ]

  # Node pools
  node_pools = [
    {
      name               = "system-pool-00"
      machine_type       = "e2-standard-2"
      min_count          = 1
      max_count          = 3
      disk_size_gb       = 50
      disk_type          = "pd-standard"
      image_type         = "COS_CONTAINERD"
      auto_repair        = true
      auto_upgrade       = true
      spot               = true
      initial_node_count = 1
    },
    {
      name               = "workload-pool-00"
      machine_type       = "e2-standard-4"
      min_count          = 0
      max_count          = 5
      disk_size_gb       = 100
      disk_type          = "pd-standard"
      image_type         = "COS_CONTAINERD"
      auto_repair        = true
      auto_upgrade       = true
      spot               = true
      initial_node_count = 0
    },
  ]

  # Security
  enable_shielded_nodes = true

  # Monitoring
  monitoring_enable_managed_prometheus = true

  # Labels
  cluster_resource_labels = merge(
    include.base.locals.standard_labels,
    {
      component = "gke"
      cluster   = "cluster-01"
    }
  )
}
