# Artifact Registry - remote proxy to GHCR

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "artifact_registry_template" {
  path           = "${get_repo_root()}/_common/templates/artifact_registry.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name = try(dependency.project.outputs.project_name, "fn-dev-01")
}

inputs = {
  project_id    = dependency.project.outputs.project_id
  location      = include.base.locals.region
  repository_id = "container-images"
  description   = "Container images for ${local.project_name} Cloud Run services"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config = {
    description                 = "GitHub Container Registry proxy"
    disable_upstream_validation = false
    docker_repository = {
      public_repository = "DOCKER_HUB"
    }
  }

  cleanup_policies = {
    "delete-untagged" = {
      action = "DELETE"
      condition = {
        tag_state  = "UNTAGGED"
        older_than = "604800s"
      }
    }
  }

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "artifact-registry"
      format    = "docker"
      purpose   = "container-images"
    }
  )
}
