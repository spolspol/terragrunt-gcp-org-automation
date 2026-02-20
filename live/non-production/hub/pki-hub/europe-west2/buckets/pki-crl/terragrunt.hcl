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
    project_id     = "org-pki-hub"
    project_name   = "pki-hub"
    project_number = "000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "apply"]
  skip_outputs                            = false
}

locals {
  bucket_name = "org-pki-crl"
}

inputs = {
  project_id       = dependency.project.outputs.project_id
  names            = [local.bucket_name]
  location         = "europe-west2"
  storage_class    = "STANDARD"
  randomize_suffix = true

  versioning = {
    for name in [local.bucket_name] :
    lower(name) => true
  }

  force_destroy = {
    for name in [local.bucket_name] :
    lower(name) => false
  }

  bucket_policy_only = {
    for name in [local.bucket_name] :
    lower(name) => true
  }

  lifecycle_rules = [
    {
      action = {
        type = "Delete"
      }
      condition = {
        age        = 90
        with_state = "ANY"
      }
    }
  ]

  labels = merge(
    try(dependency.project.outputs.labels, {}),
    {
      environment = "hub"
      purpose     = "pki-crl"
      component   = "storage"
    }
  )

  bucket_admins = {
    (local.bucket_name) = format(
      "serviceAccount:service-%s@gcp-sa-privateca.iam.gserviceaccount.com",
      dependency.project.outputs.project_number
    )
  }

  bucket_storage_admins = {
    (local.bucket_name) = format(
      "serviceAccount:service-%s@gcp-sa-privateca.iam.gserviceaccount.com",
      dependency.project.outputs.project_number
    )
  }
}
