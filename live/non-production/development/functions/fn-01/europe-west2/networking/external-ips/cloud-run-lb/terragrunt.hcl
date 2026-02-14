# Global external IP for Cloud Run load balancer

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "external_ip_template" {
  path           = "${get_repo_root()}/_common/templates/external_ip.hcl"
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

inputs = {
  project_id = try(dependency.project.outputs.project_id, "mock-project-id")
  region     = include.base.locals.region

  names = ["${try(dependency.project.outputs.project_name, "mock-project-name")}-${include.base.locals.resource_name}"]

  address_type     = "EXTERNAL"
  global           = true
  ip_version       = "IPV4"
  environment_type = include.base.locals.environment_type

  description = "Reserved global external IP for Cloud Run services load balancer"

  labels = merge(include.base.locals.standard_labels, {
    component = "external-ip"
    purpose   = "load-balancer"
    region    = include.base.locals.region
  })
}
