# Folder IAM Bindings Template
# Standardized folder-level IAM binding management for GCP folders.
#
# Notes:
# - Prefer `mode = "additive"` to avoid unintentionally removing existing IAM.
# - This is folder-level IAM. For project/org IAM, use the respective templates.

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-iam.git//modules/folders_iam?ref=${local.module_versions.iam}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
}

inputs = {
  # Required - supply at least one folder ID in consuming configs
  folders = []

  # Safe default
  mode = "additive"

  # Role -> members
  bindings = {}

  # Optional conditional bindings (see module docs)
  conditional_bindings = []
}
