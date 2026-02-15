# GitHub Container Registry authentication for GKE image pulls

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "secrets_common" {
  path   = find_in_parent_folders("secrets.hcl")
  expose = true
}

include "secret_template" {
  path           = "${get_repo_root()}/_common/templates/secret_manager.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id            = "mock-project-id"
    service_account_email = "mock-sa@mock-project-id.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  secret_name  = include.base.locals.resource_name
  secret_value = get_env("TF_VAR_github_ghcr_token", "")
}

inputs = {
  project_id = try(dependency.project.outputs.project_id, "mock-project-id")
  user_managed_replication = {
    "${local.secret_name}" = [
      { location = include.base.locals.region, kms_key_name = "" }
    ]
  }
  secrets = [
    {
      name           = local.secret_name
      secret_data    = local.secret_value != "" ? local.secret_value : null
      create_version = local.secret_value != "" ? true : false
    }
  ]
  secret_accessors_list = [
    "serviceAccount:${try(dependency.project.outputs.service_account_email, "mock-sa@mock-project-id.iam.gserviceaccount.com")}",
  ]
  labels = {
    "${local.secret_name}" = merge(
      include.secrets_common.locals.common_secret_labels,
      {
        secret_type = "container-registry-token"
        purpose     = "github-container-registry-auth"
        environment = include.base.locals.environment
        registry    = "ghcr-io"
        used_by     = "gke-image-pulls"
      }
    )
  }
}
