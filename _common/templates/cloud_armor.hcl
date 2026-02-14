terraform {
  source = "git::https://github.com/GoogleCloudPlatform/terraform-google-cloud-armor.git?ref=${local.module_versions.cloud_armor}"
}

locals {
  common_vars     = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")
  module_versions = local.common_vars.locals.module_versions
}

inputs = {
  type                = "CLOUD_ARMOR"
  default_rule_action = "deny(403)"
}
