terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-cloud-dns.git?ref=${local.module_versions.cloud_dns}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  zone_name          = basename(get_terragrunt_dir())
  zone_resource_name = replace(replace(local.zone_name, ".", "-"), "_", "-")
}

inputs = {
  project_id     = null
  type           = "peering"
  visibility     = "private"
  name           = local.zone_resource_name
  domain         = "${local.zone_name}."
  description    = "Managed by Terragrunt"
  dnssec_config  = null
  target_network = null
  labels = merge(
    local.common_vars.locals.labels,
    {
      zone_type  = "peering"
      managed_by = "terragrunt"
      zone_name  = local.zone_resource_name
    }
  )
}
