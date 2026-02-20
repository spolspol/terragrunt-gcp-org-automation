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
    project_id   = "org-vpn-gateway"
    project_name = "org-vpn-gateway"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "vpn_server_sa" {
  config_path = "../../../iam-service-accounts/vpn-server"

  mock_outputs = {
    email     = "vpn-server@org-vpn-gateway.iam.gserviceaccount.com"
    iam_email = "serviceAccount:vpn-server@org-vpn-gateway.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  bucket_folder_name = include.base.locals.resource_name
}

inputs = {
  project_id = dependency.project.outputs.project_id
  location   = include.base.locals.region

  names = ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"]

  storage_class            = "STANDARD"
  public_access_prevention = "enforced"
  randomize_suffix         = false

  versioning = {
    for name in ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"] :
    lower(name) => true
  }
  force_destroy = {
    for name in ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"] :
    lower(name) => false
  }
  bucket_policy_only = {
    for name in ["${dependency.project.outputs.project_name}-${local.bucket_folder_name}"] :
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

  viewers = [dependency.vpn_server_sa.outputs.iam_email]

  labels = {
    component   = "storage"
    cost_center = "infrastructure"
    environment = "hub"
    purpose     = "vm-scripts"
    service     = "vpn-server"
    managed_by  = "terragrunt"
  }
}
