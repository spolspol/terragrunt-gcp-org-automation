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

# Stack-aware dependency - reference the folder unit from the stack
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
  # Use folder name for project naming with optional prefix
  base_project_name = basename(dirname(get_terragrunt_dir()))
  project           = include.base.locals.name_prefix != "" ? "${include.base.locals.name_prefix}-${local.base_project_name}" : local.base_project_name

  # Billing account from account vars
  billing_account_id = include.base.locals.merged.billing_account

  # Use organization ID from account variables instead of hardcoding
  organization_id = include.base.locals.merged.org_id

  # Base folder name for reference
  base_folder_name = basename(dirname(dirname(get_terragrunt_dir())))

  # Prefixed project name for use in inputs
  prefixed_project_name = local.project

  # Billing reports bucket
  environment_usage_bucket_name = include.base.locals.merged.environment_usage_bucket_name
}

inputs = {
  # Required project parameters
  name            = local.prefixed_project_name
  project_id      = include.base.locals.merged.project_id
  org_id          = local.organization_id
  billing_account = local.billing_account_id
  folder_id       = dependency.folder.outputs.ids["hub"]

  # Environment-specific labels
  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "project"
    }
  )

  # Environment-specific settings for non-production
  lien                        = false
  disable_services_on_destroy = true
  deletion_policy             = "DELETE"

  # Use DNS-specific APIs from project.hcl, plus essential project management APIs
  activate_apis = concat(
    try(include.base.locals.merged.activate_apis, []),
    [
      "billingbudgets.googleapis.com",
      "cloudbilling.googleapis.com",
      "cloudquotas.googleapis.com",
      "essentialcontacts.googleapis.com",
      "serviceusage.googleapis.com",
      "storage-component.googleapis.com",
      "storage.googleapis.com"
    ]
  )

  # Budget configuration for DNS infrastructure
  budget_amount           = 50.00 # $50 USD monthly budget for DNS infrastructure
  budget_alert_thresholds = [0.5, 0.75, 0.9, 1.0]

  # Essential contacts for notifications
  essential_contacts = {}

  # Enable audit logging
  enable_audit_logs = true

  # Service account configuration
  create_project_sa = true
  project_sa_name   = include.base.locals.name_prefix != "" ? "${include.base.locals.name_prefix}-${include.base.locals.merged.project_id}-tofu" : "${include.base.locals.merged.project_id}-tofu"

  # Grant the project service account necessary roles
  sa_role = "roles/editor"

  # Usage bucket for exporting billing data (optional)
  usage_bucket_name   = local.environment_usage_bucket_name
  usage_bucket_prefix = local.base_project_name
}
