# Private Service Access for dp-dev-01

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "private_service_access" {
  path           = "${get_repo_root()}/_common/templates/private_service_access.hcl"
  merge_strategy = "deep"
}

dependency "network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name      = "mock-network"
    network_self_link = "projects/mock-project/global/networks/mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

locals {
  project_name = try(dependency.project.outputs.project_name, "dp-dev-01")
}

inputs = {
  project_id = dependency.project.outputs.project_id
  network    = dependency.network.outputs.network_name

  peering_range          = "10.30.200.0/24"
  name                   = "${local.project_name}-private-service-access"
  private_ip_name        = "${local.project_name}-psa-range"
  private_ip_cidr        = "10.30.200.0/24"
  private_ip_description = "Private service access for Cloud SQL and managed services in ${local.project_name}"

  labels = {
    component   = "private-service-access"
    environment = include.base.locals.environment
    project     = local.project_name
    managed_by  = "terragrunt"
  }
}
