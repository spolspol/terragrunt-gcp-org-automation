# Terragrunt template for Google Cloud Foundation Fabric CAS module.
# This keeps all CAS resources standardized without adding bespoke Terraform.

terraform {
  source = "git::https://github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-authority-service?ref=${local.module_versions.certificate_authority_service}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  default_inputs = {
    project_id = null
    location   = "europe-west2"

    ca_pool_config = {
      create_pool = null
      use_pool    = null
    }

    ca_configs            = {}
    context               = {}
    iam                   = {}
    iam_bindings          = {}
    iam_bindings_additive = {}
    iam_by_principals     = {}
  }
}

inputs = merge(
  local.default_inputs,
  try(inputs, {})
)
