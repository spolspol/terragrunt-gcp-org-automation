include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "project" {
  path = find_in_parent_folders("project.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "project_template" {
  path = "${get_repo_root()}/_common/templates/project.hcl"
}

# Stack-aware dependency - reference the folder unit from the stack
dependency "folder" {
  config_path = "../../folder"

  # Mock outputs for when the folder doesn't exist yet (for all operations)
  # The 'ids' output is a map of folder names to folder IDs from terraform-google-folders module
  mock_outputs = {
    ids = {
      "pre-development" = "123456789012345" # Folder name with prefix
      "development"     = "123456789012346" # Folder name without prefix
    }
    names = ["pre-development"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.common_vars.locals
  )

  # Use folder name for project naming with optional prefix
  name_prefix       = local.merged_vars.name_prefix != "" ? local.merged_vars.name_prefix : "tg"
  base_project_name = basename(dirname(get_terragrunt_dir()))
  project           = local.name_prefix != "" ? "${local.name_prefix}-${local.base_project_name}" : local.base_project_name
  project_id        = local.merged_vars.project_id # local.name_prefix != "" ? "${local.name_prefix}-${local.base_project_name}" : local.base_project_name

  # Billing account from account vars
  billing_account_id = local.merged_vars.billing_account

  # Use organization ID from account variables instead of hardcoding
  organization_id = local.merged_vars.org_id

  # Calculate the folder name the same way the folder creates it
  base_folder_name = basename(dirname(dirname(get_terragrunt_dir())))
  folder_name      = local.name_prefix != "" ? "${local.name_prefix}-${local.base_folder_name}" : local.base_folder_name

  # Prefixed project name for use in inputs
  prefixed_project_name = local.project
  prefixed_project_id   = local.project_id

  # Billing reports bucket
  environment_usage_bucket_name = local.merged_vars.environment_usage_bucket_name
}

# No terraform block as it's inherited from the template

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/project.hcl").inputs,
  local.merged_vars,
  {
    # Required project parameters
    # Use prefixed values from locals
    name            = local.prefixed_project_name
    project_id      = local.prefixed_project_id
    org_id          = local.organization_id
    billing_account = local.billing_account_id
    # Project will be created within the folder created by the folder dependency
    # The terraform-google-folders module outputs a map of folder names to IDs
    # Extract the folder ID for our specific folder name
    folder_id = dependency.folder.outputs.ids[local.folder_name]

    # Environment-specific labels
    labels = merge(
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {}),
      {
        component        = "project"
        environment      = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
      }
    )

    # Environment-specific settings for non-production
    lien                        = false
    disable_services_on_destroy = true
    deletion_policy             = "DELETE"

    # Additional APIs specific to this project's needs
    activate_apis = [
      "compute.googleapis.com",
      "secretmanager.googleapis.com",
      "accesscontextmanager.googleapis.com",
      "bigquery.googleapis.com",
      "bigqueryreservation.googleapis.com",
      "bigquerystorage.googleapis.com",
      "billingbudgets.googleapis.com",
      "cloudbilling.googleapis.com",
      "cloudkms.googleapis.com",
      "cloudquotas.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "datacatalog.googleapis.com",
      "essentialcontacts.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
      "networksecurity.googleapis.com",
      "servicenetworking.googleapis.com",
      "serviceusage.googleapis.com",
      "storage-component.googleapis.com",
      "storage.googleapis.com",
      "networkservices.googleapis.com",
      "networkmanagement.googleapis.com"
    ]

    # Budget configuration for cost management
    budget_amount           = 100.00 # $100 USD monthly budget for dev environment
    budget_alert_thresholds = [0.5, 0.75, 0.9, 1.0]

    # Essential contacts for notifications - using map of string lists format
    essential_contacts = {} # Empty map to avoid conflicts with environment variable

    # Enable audit logging
    enable_audit_logs = true

    # Service account configuration
    create_project_sa = true
    project_sa_name   = local.name_prefix != "" ? "${local.name_prefix}-${local.project_id}-terraform" : "${local.base_project_name}-terraform"

    # Grant the project service account necessary roles
    sa_role = "roles/editor" # Consider using more specific roles in production

    # Usage bucket for exporting billing data (optional)
    # usage_bucket_name   = "${local.name_prefix}-billing-${local.merged_vars.environment}-usage-reports"
    usage_bucket_name   = local.environment_usage_bucket_name
    usage_bucket_prefix = local.base_project_name

    # Tags for organization policy compliance
    # Manual project creation works without tags, so the issue is with the Terraform module
    # Removing tag_binding_values parameter entirely to avoid triggering tag validation
    # tag_binding_values = []  # Commented out - empty array triggers module tag validation
  }
)
