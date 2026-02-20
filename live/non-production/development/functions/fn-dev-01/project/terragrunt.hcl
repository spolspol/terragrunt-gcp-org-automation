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
      "functions" = "folders/123456789012345"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name = include.base.locals.merged.project
  project_id   = include.base.locals.merged.project_id
}

inputs = {
  name            = local.project_name
  project_id      = local.project_id
  org_id          = include.base.locals.merged.org_id
  billing_account = include.base.locals.merged.billing_account
  folder_id       = dependency.folder.outputs.ids["functions"]

  labels = merge(
    include.base.locals.standard_labels,
    {
      component        = "project"
      environment      = include.base.locals.environment
      environment_type = include.base.locals.environment_type
    }
  )

  lien                        = false
  disable_services_on_destroy = true
  deletion_policy             = "DELETE"

  activate_apis = [
    "artifactregistry.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "essentialcontacts.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "networkservices.googleapis.com",
    "privateca.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "vpcaccess.googleapis.com",
  ]

  budget_amount           = 200.00
  budget_alert_thresholds = [0.5, 0.75, 0.9, 1.0]

  essential_contacts = {
    "gcp-platform-alerts@example.com" = ["ALL"]
  }

  enable_audit_logs = true
  create_project_sa = true
  project_sa_name   = "${local.project_id}-tofu"
  sa_role           = "roles/editor"

  usage_bucket_name   = include.base.locals.merged.environment_usage_bucket_name
  usage_bucket_prefix = local.project_name
}
