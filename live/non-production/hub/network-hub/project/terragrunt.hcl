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

locals {
  base_project_name = basename(dirname(get_terragrunt_dir()))
  project           = include.base.locals.name_prefix != "" ? "${include.base.locals.name_prefix}-${local.base_project_name}" : local.base_project_name
  project_id        = include.base.locals.merged.project_id

  billing_account_id = include.base.locals.merged.billing_account
  organization_id    = include.base.locals.merged.org_id

  base_folder_name = basename(dirname(dirname(get_terragrunt_dir())))
  folder_name      = include.base.locals.name_prefix != "" ? "${include.base.locals.name_prefix}-${local.base_folder_name}" : local.base_folder_name

  prefixed_project_name = local.project
  prefixed_project_id   = local.project_id

  environment_usage_bucket_name = include.base.locals.merged.environment_usage_bucket_name
}

inputs = {
  name            = local.prefixed_project_name
  project_id      = local.prefixed_project_id
  org_id          = local.organization_id
  billing_account = local.billing_account_id
  folder_id       = dependency.folder.outputs.ids[local.folder_name]

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "project"
      purpose   = "network-connectivity"
    }
  )

  lien                        = false
  disable_services_on_destroy = true
  deletion_policy             = "DELETE"

  activate_apis = [
    "compute.googleapis.com",
    "networkconnectivity.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com",
    "networkmanagement.googleapis.com",
    "servicenetworking.googleapis.com",
    "dns.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "admin.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "billingbudgets.googleapis.com",
    "essentialcontacts.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]

  budget_amount           = 200.00
  budget_alert_thresholds = [0.5, 0.75, 0.9, 1.0]

  essential_contacts = {
    "admin@example.com" = ["ALL"]
  }

  enable_audit_logs = true
  create_project_sa = true
  project_sa_name   = "${local.base_project_name}-tofu"
  sa_role           = "roles/editor"

  usage_bucket_name   = local.environment_usage_bucket_name
  usage_bucket_prefix = local.base_project_name
  random_project_id   = false
}
