# Private DNS zone for dp-01

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_dns_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns.hcl"
  merge_strategy = "deep"
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

dependency "network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock-project/global/networks/mock-network"
    network_name      = "mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  dns_config   = read_terragrunt_config("${get_terragrunt_dir()}/../dns.hcl")
  project_name = try(dependency.project.outputs.project_name, "dp-01")
  domain       = "${local.project_name}.dev.example.io."
  zone_name    = replace(trimsuffix(local.domain, "."), ".", "-")
}

inputs = {
  project_id = dependency.project.outputs.project_id

  name   = local.zone_name
  domain = local.domain
  type   = "private"

  private_visibility_config_networks = [
    dependency.network.outputs.network_self_link
  ]

  recordsets = [
    {
      name    = "postgres-main"
      type    = "A"
      ttl     = local.dns_config.locals.default_ttl
      records = ["10.30.200.5"]
    },
  ]

  labels = merge(
    local.dns_config.locals.common_dns_labels,
    {
      environment = include.base.locals.environment
      project     = local.project_name
      zone_type   = "private"
      purpose     = "internal-dns"
    }
  )
}
