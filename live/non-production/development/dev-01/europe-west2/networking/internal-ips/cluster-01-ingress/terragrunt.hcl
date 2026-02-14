# Reserved internal IP for GKE cluster-01 ingress controller
# This IP is used by the nginx-ingress or istio-gateway within the cluster

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "internal_ip_template" {
  path           = "${get_repo_root()}/_common/templates/internal_ip.hcl"
  merge_strategy = "deep"
}

dependency "network" {
  config_path = "../../../../vpc-network"
  mock_outputs = {
    network_self_link  = "projects/mock-project/global/networks/mock-network"
    subnets_self_links = [
      "projects/mock-project/regions/europe-west2/subnetworks/mock-network-dmz",
      "projects/mock-project/regions/europe-west2/subnetworks/mock-network-private",
    ]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
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
  names      = ["${try(dependency.project.outputs.project_name, "mock-project-name")}-cluster-01-ingress"]

  # Reserve in the private subnet for internal load balancer
  subnetwork  = "projects/${try(dependency.project.outputs.project_id, "mock-project-id")}/regions/${include.base.locals.region}/subnetworks/${try(dependency.project.outputs.project_name, "mock-project-name")}-vpc-network-private"
  addresses   = ["10.10.8.10"]
  description = "Reserved internal IP for cluster-01 ingress controller"

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "internal-ip"
      purpose   = "gke-ingress"
      cluster   = "cluster-01"
    }
  )
}
