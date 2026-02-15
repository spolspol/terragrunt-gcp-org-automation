locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  project_name = basename(get_terragrunt_dir())
  project      = local.project_name
  project_id   = "${local.project_name}-d"

  name_prefix = try(local.env_vars.name_prefix, "")
  project_labels = {
    project     = local.project
    project_id  = local.project_id
    cost_center = "serverless"
    purpose     = "cloud-run-functions"
  }

  project_service_account = "${local.project_id}-tofu@${local.project_id}.iam.gserviceaccount.com"

  project_settings = {}

  service_account_roles = [
    "roles/run.invoker",
    "roles/storage.objectViewer"
  ]
}
