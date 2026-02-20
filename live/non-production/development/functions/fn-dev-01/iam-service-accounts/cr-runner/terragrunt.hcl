# Cloud Run Runner service account
# Shared runtime identity for Cloud Run services

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "service_account_template" {
  path           = "${get_repo_root()}/_common/templates/service_account.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = {
  project_id   = dependency.project.outputs.project_id
  account_id   = "cr-runner"
  display_name = "Cloud Run Runner"
  description  = "Shared runtime service account for Cloud Run services"

  generate_keys = false

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "service-account"
      purpose   = "cloud-run-runtime"
    }
  )
}
