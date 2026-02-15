include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_router_template" {
  path           = "${get_repo_root()}/_common/templates/cloud-router.hcl"
  merge_strategy = "deep"
}

dependency "vpc-network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name = "mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
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

inputs = {
  project = dependency.project.outputs.project_id
  region  = include.base.locals.region
  network = dependency.vpc-network.outputs.network_name
  name    = "${dependency.project.outputs.project_name}-router"
  asn     = 64512

  labels = merge(
    include.base.locals.standard_labels,
    {
      component    = "cloud-router"
      project_name = dependency.project.outputs.project_name
    }
  )
}
