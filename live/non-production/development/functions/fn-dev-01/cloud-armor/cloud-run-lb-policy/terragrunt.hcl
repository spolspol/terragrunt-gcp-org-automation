# Cloud Armor policy for Cloud Run load balancer

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_armor_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_armor.hcl"
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
  project_id  = dependency.project.outputs.project_id
  name        = "${local.project_name}-cloud-run-lb-policy"
  description = "Cloud Armor policy for ${local.project_name} Cloud Run load balancer"

  default_rule_action = "deny(403)"

  security_rules = {
    "allow-vpn-access" = {
      action        = "allow"
      priority      = 1000
      description   = "Allow access from VPN gateway"
      src_ip_ranges = ["10.11.0.0/16"]
      preview       = false
    }
    "allow-office-ips" = {
      action        = "allow"
      priority      = 1100
      description   = "Allow access from office IP ranges"
      src_ip_ranges = ["203.0.113.0/24"]
      preview       = false
    }
  }
}
