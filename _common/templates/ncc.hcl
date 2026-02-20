terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-network.git//modules/network-connectivity-center?ref=${local.module_versions.network_connectivity_center}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
  common_tags     = try(local.common_vars.locals.common_tags, {})
}

inputs = {
  project_id          = ""
  ncc_hub_name        = ""
  ncc_hub_description = null
  ncc_hub_labels = merge(
    {
      managed_by = "terragrunt"
      component  = "network-connectivity"
    },
    local.common_tags
  )
  spoke_labels = merge(
    {
      managed_by = "terragrunt"
      component  = "network-connectivity"
    },
    local.common_tags
  )
  export_psc              = false
  vpc_spokes              = {}
  hybrid_spokes           = {}
  router_appliance_spokes = {}
}
