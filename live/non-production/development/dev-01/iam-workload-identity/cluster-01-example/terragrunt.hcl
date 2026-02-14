# Example Workload Identity binding
# Binds a GCP Service Account (GSA) to a Kubernetes Service Account (KSA)
# Pattern: GSA <cluster>-<app> -> KSA <namespace>/<ksa-name>

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "workload_identity_template" {
  path           = "${get_repo_root()}/_common/templates/workload_identity.hcl"
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

dependency "cluster" {
  config_path = "../../europe-west2/gke/cluster-01"
  mock_outputs = {
    cluster_id = "projects/mock-project-id/locations/europe-west2/clusters/cluster-01"
    name       = "cluster-01"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  # Derive cluster ID and app name from directory structure
  # Directory name format: <cluster>-<app-name>
  dir_name   = basename(get_terragrunt_dir())
  cluster_id = split("-", local.dir_name)[0]

  # Workload Identity configuration
  namespace = "argocd"
  ksa_name  = "argocd-server"
}

inputs = {
  project_id = dependency.project.outputs.project_id

  # GSA configuration
  name         = "${include.base.locals.resource_name}"
  display_name = "Workload Identity SA for ${local.namespace}/${local.ksa_name}"
  description  = "Service account bound to KSA ${local.ksa_name} in namespace ${local.namespace} on ${dependency.cluster.outputs.name}"

  # KSA binding
  namespace = local.namespace
  ksa_name  = local.ksa_name

  # Labels
  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "workload-identity"
      cluster   = dependency.cluster.outputs.name
      namespace = local.namespace
      ksa       = local.ksa_name
    }
  )
}
