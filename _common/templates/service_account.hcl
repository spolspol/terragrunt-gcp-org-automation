# Service Account Template (Singular)
# Creates a single service account per directory using simple-sa submodule
#
# Structure: iam-service-accounts/<sa-name>/terragrunt.hcl
#
# Notes:
# - Uses simple-sa submodule for cleaner single-SA creation
# - SA name derived from directory name (basename)
# - Avoid generating keys; use Workload Identity or IAM bindings
# - Prefer managing IAM via iam-bindings/ module for complex bindings

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-service-accounts.git//modules/simple-sa?ref=${local.module_versions.service_accounts}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Derive SA name from directory name
  sa_name = basename(get_terragrunt_dir())
}

# Default inputs - override in child module
inputs = {
  # Required - must be provided by consuming Terragrunt configs
  project_id = null

  # SA name derived from directory name by default
  name = local.sa_name

  # Metadata
  display_name = "Terraform-managed service account"
  description  = ""

  # Optional project roles (prefer using iam-bindings/ module for complex bindings)
  project_roles = []
}
