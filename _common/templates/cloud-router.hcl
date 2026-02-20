terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-cloud-router.git//?ref=${local.module_versions.cloud_router}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
}

inputs = {
  # Default values - override in terragrunt.hcl
  project = ""
  region  = ""
  network = ""
  name    = ""
  asn     = 64512

  # Default labels
  labels = merge(
    {
      managed_by = "terragrunt"
      component  = "cloud-router"
    },
    try(local.common_vars.locals.common_tags, {})
  )
}
