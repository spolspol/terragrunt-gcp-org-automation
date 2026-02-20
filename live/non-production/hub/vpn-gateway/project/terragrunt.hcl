include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "project_template" {
  path           = "${get_repo_root()}/_common/templates/project.hcl"
  merge_strategy = "deep"
}

locals {
  base_folder_name = basename(dirname(dirname(get_terragrunt_dir())))
  folder_name      = include.base.locals.name_prefix != "" ? "${include.base.locals.name_prefix}-${local.base_folder_name}" : local.base_folder_name

  environment_usage_bucket_name = include.base.locals.merged.environment_usage_bucket_name
}

dependency "folder" {
  config_path = "../../folder"
  mock_outputs = {
    ids = {
      "hub" = "123456789012345"
    }
    names = ["hub"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  name            = include.base.locals.merged.project_id
  project_id      = include.base.locals.merged.project_id
  billing_account = include.base.locals.merged.billing_account
  folder_id       = dependency.folder.outputs.ids[local.folder_name]

  auto_create_network = false

  usage_bucket_name   = local.environment_usage_bucket_name
  usage_bucket_prefix = include.base.locals.merged.project_id

  activate_apis = [
    "compute.googleapis.com",
    "networkconnectivity.googleapis.com",
    "networkmanagement.googleapis.com",
    "dns.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "billingbudgets.googleapis.com",
    "servicenetworking.googleapis.com",
    "oslogin.googleapis.com",
  ]

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "project"
      purpose   = "vpn-gateway"
    }
  )
}
