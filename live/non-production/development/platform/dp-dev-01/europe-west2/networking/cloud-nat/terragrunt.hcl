include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_nat_template" {
  path           = "${get_repo_root()}/_common/templates/cloud-nat.hcl"
  merge_strategy = "deep"
}

dependency "cloud-router" {
  config_path = "../cloud-router"
  mock_outputs = {
    router = {
      name = "mock-router"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "external-ip" {
  config_path = "../external-ips/nat-gateway"
  mock_outputs = {
    addresses  = ["mock-nat-ip"]
    self_links = ["https://www.googleapis.com/compute/v1/projects/mock-project-id/regions/europe-west2/addresses/mock-nat-ip"]
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
  project_id = dependency.project.outputs.project_id
  region     = include.base.locals.region
  router     = dependency.cloud-router.outputs.router.name
  name       = "${dependency.project.outputs.project_name}-nat"
  nat_ips    = dependency.external-ip.outputs.self_links

  source_subnets_list = [
    "${dependency.project.outputs.project_name}-vpc-network-gke",
    "${dependency.project.outputs.project_name}-vpc-network-public"
  ]

  nat_min_ports_per_vm = 64
  nat_max_ports_per_vm = 65536
  enable_logging       = true
  log_config_filter    = "ALL"

  nat_udp_idle_timeout_sec             = 30
  nat_icmp_idle_timeout_sec            = 30
  nat_tcp_established_idle_timeout_sec = 1200
  nat_tcp_transitory_idle_timeout_sec  = 30

  labels = merge(
    include.base.locals.standard_labels,
    {
      component    = "cloud-nat"
      project_name = dependency.project.outputs.project_name
    }
  )
}
