# GKE Module Template
# This template provides standardized Google Kubernetes Engine cluster configurations
# Include this template in your Terragrunt configurations for consistent GKE setups
# Uses terraform-google-kubernetes-engine module's private-cluster submodule v37.0.0

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git//modules/private-cluster?ref=${local.module_versions.gke}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Default GKE configuration for v37.0.0
  default_gke_config = {
    # Cluster basics
    kubernetes_version = "latest"
    release_channel    = "REGULAR"

    # Private cluster settings
    enable_private_endpoint      = false
    enable_private_nodes         = true
    master_ipv4_cidr_block       = "172.16.0.0/28"
    master_global_access_enabled = false

    # Security features
    enable_shielded_nodes       = true
    enable_binary_authorization = false # Start with false, enable per environment
    network_policy              = true
    # sandbox_config should be in node pools, not cluster level

    # Networking features (new in v37)
    enable_l4_ilb_subsetting = false
    # enable_multi_networking not supported in v37.0.0
    enable_fqdn_network_policy               = false
    enable_cilium_clusterwide_network_policy = false
    # allow_net_admin is a node pool setting, not cluster level
    dns_cache = false

    # Storage and backup (new in v37)
    enable_gcfs             = false # Google Cloud Filestore CSI driver
    gke_backup_agent_config = false # Enable in production with true
    stateful_ha             = false

    # Addons
    horizontal_pod_autoscaling = true
    http_load_balancing        = true
    network_policy_provider    = "CALICO"
    gce_pd_csi_driver          = true
    filestore_csi_driver       = false
    gcs_fuse_csi_driver        = false

    # Monitoring and logging
    logging_service                      = "logging.googleapis.com/kubernetes"
    monitoring_service                   = "monitoring.googleapis.com/kubernetes"
    monitoring_enable_managed_prometheus = false
    monitoring_enabled_components        = ["SYSTEM_COMPONENTS"]
    logging_enabled_components           = ["SYSTEM_COMPONENTS", "WORKLOADS"]

    # Daily maintenance window (5AM UTC daily, 4-hour window)
    maintenance_start_time = "05:00"

    # Workload identity and security
    # workload_identity is configured via identity_namespace parameter
    identity_namespace = "enabled"

    # Node management
    remove_default_node_pool = true
    grant_registry_access    = true

    # Service account configuration
    create_service_account = true
    service_account_name   = "" # Will be overridden in implementations

    # Cost optimization
    enable_cost_allocation           = true
    resource_usage_export_dataset_id = ""

    # Fleet management (new in v37)
    fleet_project = null

    # Deletion protection
    deletion_protection = false # Set to false for development environments
  }

  # Environment-specific node pool configurations
  env_node_pool_configs = {
    production = {
      initial_node_count        = 3
      min_count                 = 3
      max_count                 = 10
      machine_type              = "n2-standard-4"
      disk_size_gb              = 100
      disk_type                 = "pd-ssd"
      preemptible               = false
      spot                      = false
      auto_repair               = true
      auto_upgrade              = true
      enable_gvnic              = true # Google Virtual NIC for better performance
      enable_fast_socket        = true # New in v37
      enable_confidential_nodes = false
    }
    non-production = {
      initial_node_count        = 1
      min_count                 = 1
      max_count                 = 3
      machine_type              = "e2-standard-2"
      disk_size_gb              = 50
      disk_type                 = "pd-standard"
      preemptible               = false
      spot                      = true
      auto_repair               = true
      auto_upgrade              = true
      enable_gvnic              = false
      enable_fast_socket        = false
      enable_confidential_nodes = false
    }
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters (must be provided by implementation)
  project_id        = null
  name              = null
  region            = null
  network           = null
  subnetwork        = null
  ip_range_pods     = null
  ip_range_services = null

  # Cluster configuration
  kubernetes_version = try(inputs.kubernetes_version, local.default_gke_config.kubernetes_version)
  release_channel    = try(inputs.release_channel, local.default_gke_config.release_channel)

  # Private cluster configuration
  enable_private_endpoint      = try(inputs.enable_private_endpoint, local.default_gke_config.enable_private_endpoint)
  enable_private_nodes         = try(inputs.enable_private_nodes, local.default_gke_config.enable_private_nodes)
  master_ipv4_cidr_block       = try(inputs.master_ipv4_cidr_block, local.default_gke_config.master_ipv4_cidr_block)
  master_global_access_enabled = try(inputs.master_global_access_enabled, local.default_gke_config.master_global_access_enabled)

  # DNS configuration (new in v37)
  dns_cache = try(inputs.dns_cache, local.default_gke_config.dns_cache)

  # Security features
  enable_shielded_nodes       = try(inputs.enable_shielded_nodes, local.default_gke_config.enable_shielded_nodes)
  enable_binary_authorization = try(inputs.enable_binary_authorization, local.default_gke_config.enable_binary_authorization)
  network_policy              = try(inputs.network_policy, local.default_gke_config.network_policy)
  # sandbox_config is now in node pools, not cluster level

  # Deletion protection
  deletion_protection = try(inputs.deletion_protection, local.default_gke_config.deletion_protection)

  # Advanced networking (new in v37)
  enable_l4_ilb_subsetting = try(inputs.enable_l4_ilb_subsetting, local.default_gke_config.enable_l4_ilb_subsetting)
  # enable_multi_networking not supported in v37.0.0
  enable_fqdn_network_policy               = try(inputs.enable_fqdn_network_policy, local.default_gke_config.enable_fqdn_network_policy)
  enable_cilium_clusterwide_network_policy = try(inputs.enable_cilium_clusterwide_network_policy, local.default_gke_config.enable_cilium_clusterwide_network_policy)
  # allow_net_admin is a node pool setting

  # Storage features (enhanced in v37)
  enable_gcfs          = try(inputs.enable_gcfs, local.default_gke_config.enable_gcfs)
  gce_pd_csi_driver    = try(inputs.gce_pd_csi_driver, local.default_gke_config.gce_pd_csi_driver)
  filestore_csi_driver = try(inputs.filestore_csi_driver, local.default_gke_config.filestore_csi_driver)
  gcs_fuse_csi_driver  = try(inputs.gcs_fuse_csi_driver, local.default_gke_config.gcs_fuse_csi_driver)

  # Backup and HA (new in v37)
  gke_backup_agent_config = try(inputs.gke_backup_agent_config, local.default_gke_config.gke_backup_agent_config)
  stateful_ha             = try(inputs.stateful_ha, local.default_gke_config.stateful_ha)

  # Workload Identity
  # Workload identity is configured via identity_namespace
  identity_namespace = try(inputs.identity_namespace, local.default_gke_config.identity_namespace)

  # Default node pool management
  remove_default_node_pool = try(inputs.remove_default_node_pool, local.default_gke_config.remove_default_node_pool)

  # Registry access
  grant_registry_access = try(inputs.grant_registry_access, local.default_gke_config.grant_registry_access)

  # Service account configuration
  create_service_account = try(inputs.create_service_account, local.default_gke_config.create_service_account)
  service_account_name   = try(inputs.service_account_name, local.default_gke_config.service_account_name)

  # Addons
  horizontal_pod_autoscaling = try(inputs.horizontal_pod_autoscaling, local.default_gke_config.horizontal_pod_autoscaling)
  http_load_balancing        = try(inputs.http_load_balancing, local.default_gke_config.http_load_balancing)
  network_policy_provider    = try(inputs.network_policy_provider, local.default_gke_config.network_policy_provider)

  # Monitoring and logging (enhanced in v37)
  logging_service                      = try(inputs.logging_service, local.default_gke_config.logging_service)
  monitoring_service                   = try(inputs.monitoring_service, local.default_gke_config.monitoring_service)
  monitoring_enable_managed_prometheus = try(inputs.monitoring_enable_managed_prometheus, local.default_gke_config.monitoring_enable_managed_prometheus)
  monitoring_enabled_components        = try(inputs.monitoring_enabled_components, local.default_gke_config.monitoring_enabled_components)
  logging_enabled_components           = try(inputs.logging_enabled_components, local.default_gke_config.logging_enabled_components)

  # Cost management (new in v37)
  enable_cost_allocation           = try(inputs.enable_cost_allocation, local.default_gke_config.enable_cost_allocation)
  resource_usage_export_dataset_id = try(inputs.resource_usage_export_dataset_id, local.default_gke_config.resource_usage_export_dataset_id)

  # Maintenance window (daily maintenance window only needs start_time)
  maintenance_start_time = try(inputs.maintenance_start_time, local.default_gke_config.maintenance_start_time)

  # Master authorized networks
  master_authorized_networks = try(inputs.master_authorized_networks, [])

  # Fleet management (new in v37)
  fleet_project = try(inputs.fleet_project, local.default_gke_config.fleet_project)

  # Node pools configuration
  node_pools = try(inputs.node_pools, [
    {
      name                      = "default-pool"
      initial_node_count        = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].initial_node_count
      min_count                 = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].min_count
      max_count                 = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].max_count
      machine_type              = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].machine_type
      disk_size_gb              = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].disk_size_gb
      disk_type                 = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].disk_type
      preemptible               = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].preemptible
      spot                      = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].spot
      auto_repair               = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].auto_repair
      auto_upgrade              = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].auto_upgrade
      enable_gvnic              = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].enable_gvnic
      enable_fast_socket        = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].enable_fast_socket
      enable_confidential_nodes = local.env_node_pool_configs[try(inputs.environment_type, "non-production")].enable_confidential_nodes
      # Example sandbox_config for node pool (uncomment to enable)
      # sandbox_config = {
      #   sandbox_type = "gvisor"
      # }
    }
  ])

  # Node pools OAuth scopes
  node_pools_oauth_scopes = try(inputs.node_pools_oauth_scopes, {
    all = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  })

  # Node pools labels
  node_pools_labels = try(inputs.node_pools_labels, {
    all = {
      managed_by = "terragrunt"
      component  = "gke"
    }
  })

  # Node pools metadata
  node_pools_metadata = try(inputs.node_pools_metadata, {
    all = {
      disable-legacy-endpoints = "true"
    }
  })

  # Node pools tags
  node_pools_tags = try(inputs.node_pools_tags, {
    all = ["gke-node", "terragrunt-managed"]
  })

  # Cluster resource labels
  cluster_resource_labels = try(inputs.cluster_resource_labels, {
    managed_by = "terragrunt"
    component  = "gke"
  })
}
