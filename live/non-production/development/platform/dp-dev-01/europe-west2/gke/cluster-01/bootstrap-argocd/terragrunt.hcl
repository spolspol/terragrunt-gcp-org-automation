# ArgoCD bootstrap for cluster-01

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "argocd_template" {
  path           = "${get_repo_root()}/_common/templates/argocd.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "cluster" {
  config_path = "../"
  mock_outputs = {
    name       = "dp-dev-01-ew2-cluster-01"
    endpoint   = "https://172.16.0.48"
    ca_certificate = "LS0tLS1CRUdJTi..."
    cluster_id = "projects/mock-project-id/locations/europe-west2/clusters/dp-dev-01-ew2-cluster-01"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name = try(dependency.project.outputs.project_name, "dp-dev-01")
  base_domain  = "${local.project_name}.dev.example.io"
}

inputs = {
  project_id   = dependency.project.outputs.project_id
  cluster_name = dependency.cluster.outputs.name
  cluster_endpoint    = dependency.cluster.outputs.endpoint
  cluster_ca_cert     = dependency.cluster.outputs.ca_certificate

  argocd_chart_version = "9.4.2"

  bootstrap_repo = {
    url      = "https://github.com/example-org/gke-argocd-cluster-gitops-poc.git"
    revision = "main"
    path     = "bootstrap"
  }

  base_domain = local.base_domain

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "argocd"
      cluster   = dependency.cluster.outputs.name
    }
  )
}
