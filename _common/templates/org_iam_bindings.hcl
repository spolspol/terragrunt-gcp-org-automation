# Organization IAM Bindings Template
# Standardized organization-level IAM binding management for GCP orgs.
#
# Notes:
# - Prefer `mode = "additive"` to avoid unintentionally removing existing org IAM.
# - This is org-level IAM. For project-level IAM, use `_common/templates/iam_bindings.hcl`.

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-iam.git//modules/organizations_iam?ref=${local.module_versions.iam}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
}

inputs = {
  # Required - supply at least one org id in consuming configs
  organizations = []

  # Safe default
  mode = "additive"

  # Role -> members
  bindings = {}

  # Optional conditional bindings (see module docs)
  conditional_bindings = []
}
