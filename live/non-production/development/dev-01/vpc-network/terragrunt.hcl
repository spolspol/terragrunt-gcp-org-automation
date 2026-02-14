include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "network_template" {
  path           = "${get_repo_root()}/_common/templates/network.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  network_name = "${dependency.project.outputs.project_name}-vpc-network"
}

inputs = {
  project_id       = try(dependency.project.outputs.project_id, "mock-project-id")
  network_name     = local.network_name
  environment_type = include.base.locals.environment_type

  subnets = [
    {
      # DMZ subnet - for bastion hosts, jump boxes, and publicly-facing services
      subnet_name           = "${local.network_name}-dmz"
      subnet_ip             = "10.10.0.0/21"
      subnet_region         = include.base.locals.region
      subnet_private_access = true
      subnet_flow_logs      = true
      description           = "DMZ subnet for ${dependency.project.outputs.project_name}"
    },
    {
      # Private subnet - for internal services, databases, and backend workloads
      subnet_name           = "${local.network_name}-private"
      subnet_ip             = "10.10.8.0/21"
      subnet_region         = include.base.locals.region
      subnet_private_access = true
      subnet_flow_logs      = true
      description           = "Private subnet for ${dependency.project.outputs.project_name}"
    },
    {
      # Public subnet - for services requiring internet access via NAT
      subnet_name           = "${local.network_name}-public"
      subnet_ip             = "10.10.16.0/21"
      subnet_region         = include.base.locals.region
      subnet_private_access = true
      subnet_flow_logs      = false
      description           = "Public subnet for ${dependency.project.outputs.project_name}"
    },
    {
      # GKE subnet - dedicated subnet for GKE nodes with secondary ranges for pods/services
      subnet_name           = "${local.network_name}-gke"
      subnet_ip             = "10.10.64.0/20"
      subnet_region         = include.base.locals.region
      subnet_private_access = true
      subnet_flow_logs      = true
      description           = "GKE subnet for ${dependency.project.outputs.project_name}"
    },
    {
      # CloudRun/Serverless subnet - for VPC connector or Direct VPC egress
      subnet_name           = "${local.network_name}-serverless"
      subnet_ip             = "10.10.96.0/23"
      subnet_region         = include.base.locals.region
      subnet_private_access = true
      subnet_flow_logs      = false
      description           = "Serverless subnet for ${dependency.project.outputs.project_name}"
    },
  ]

  # Secondary IP ranges for GKE pods and services
  secondary_ranges = {
    "${local.network_name}-gke" = [
      {
        range_name    = "cluster-01-pods"
        ip_cidr_range = "10.10.128.0/17"
      },
      {
        range_name    = "cluster-01-services"
        ip_cidr_range = "10.10.112.0/20"
      },
    ]
  }

  network_labels = merge(
    include.base.locals.standard_labels,
    {
      component = "network"
    }
  )
}
