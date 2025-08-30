# Cloud NAT Configuration
# Provides NAT gateway for private GKE nodes and compute instances

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

include "cloud_nat_template" {
  path = "${get_repo_root()}/_common/templates/cloud-nat.hcl"
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
  
  # Dynamic path construction
  networking_base_path = dirname(get_terragrunt_dir())
}

dependency "project" {
  config_path = find_in_parent_folders("project")
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "cloud-router" {
  config_path = "${local.networking_base_path}/cloud-router"
  mock_outputs = {
    router_name = "mock-router"
    router_id   = "projects/mock-project/regions/europe-west2/routers/mock-router"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "nat-gateway-ip" {
  config_path = "${local.networking_base_path}/external-ips/nat-gateway"
  mock_outputs = {
    addresses = ["35.246.0.1"]
    self_links = ["projects/mock-project/regions/europe-west2/addresses/nat-gateway"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  project_id = dependency.project.outputs.project_id
  region     = local.merged_vars.region
  
  # NAT configuration
  nat_name    = "${dependency.project.outputs.project_name}-${local.merged_vars.region}-nat"
  router_name = dependency.cloud-router.outputs.router_name
  
  # NAT IP allocation
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = dependency.nat-gateway-ip.outputs.self_links
  
  # Source subnet configuration
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  # Logging configuration
  enable_endpoint_independent_mapping = true
  log_config = {
    enable = true
    filter = "ERRORS_ONLY"
  }
  
  # Minimum ports per VM
  min_ports_per_vm = 64
  
  # TCP timeouts
  tcp_established_idle_timeout_sec = 1200
  tcp_transitory_idle_timeout_sec  = 30
  tcp_time_wait_timeout_sec        = 120
  
  # UDP timeout
  udp_idle_timeout_sec = 30
  
  # ICMP timeout
  icmp_idle_timeout_sec = 30
}