locals {
  # Organization/Account level variables
  org_id = "YOUR_ORG_ID" # Replace with your actual organization ID

  # Billing Account ID for all projects in this account
  billing_account = "YOUR_BILLING_ACCOUNT"

  # Org/Account-level service account for organization-wide operations
  org_service_account = "tofu-sa-org@org-automation.iam.gserviceaccount.com"

  # Default org-level labels to inherit
  org_labels = {
    managed_by = "terragrunt"
    org        = "example-org"
  }

  # Note: name_prefix is now set at the environment level in env.hcl
}
