terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-cloud-nat.git//?ref=${local.module_versions.cloud_nat}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
}

inputs = {
  # Default values - override in terragrunt.hcl
  project_id          = ""
  region              = ""
  router              = ""
  name                = ""
  nat_ips             = []
  source_subnets_list = []
  drain_nat_ips       = []

  # Default NAT configuration
  nat_min_ports_per_vm = 64
  nat_max_ports_per_vm = 65536
  enable_logging       = true
  log_config_filter    = "ALL"

  # Timeout settings
  nat_udp_idle_timeout_sec             = 30
  nat_icmp_idle_timeout_sec            = 30
  nat_tcp_established_idle_timeout_sec = 1200
  nat_tcp_transitory_idle_timeout_sec  = 30

  # Default labels
  labels = merge(
    {
      managed_by = "terragrunt"
      component  = "cloud-nat"
    },
    try(local.common_vars.locals.common_tags, {})
  )
}