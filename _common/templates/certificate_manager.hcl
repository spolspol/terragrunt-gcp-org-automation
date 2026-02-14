# Terragrunt template for Google Cloud Foundation Fabric Certificate Manager module.
# This keeps all Certificate Manager resources standardized without adding bespoke Terraform.

terraform {
  source = "git::https://github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-manager?ref=${local.module_versions.certificate_manager}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  default_inputs = {
    project_id = null
  }
}

inputs = merge(
  local.default_inputs,
  try(inputs, {})
)
