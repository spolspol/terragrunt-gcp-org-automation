# Cloud Storage bucket for compute logs

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "bucket_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_storage.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name = try(dependency.project.outputs.project_name, "dp-dev-01")
  bucket_name  = "${local.project_name}-compute-logs"
}

inputs = {
  project_id = dependency.project.outputs.project_id
  name       = local.bucket_name
  location   = include.base.locals.region

  storage_class = "STANDARD"
  versioning    = false
  force_destroy = true

  lifecycle_rules = [
    {
      action = {
        type = "Delete"
      }
      condition = {
        age = 30
      }
    }
  ]

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "cloud-storage"
      purpose   = "compute-logs"
    }
  )
}
