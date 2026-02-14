# External Application Load Balancer for Cloud Run services

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "load_balancer_template" {
  path           = "${get_repo_root()}/_common/templates/load_balancer.hcl"
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

dependency "external_ip" {
  config_path = "../../networking/external-ips/cloud-run-lb"
  mock_outputs = {
    addresses = ["0.0.0.0"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "cert_map" {
  config_path = "../../certificate-manager/api-lb-cert"
  mock_outputs = {
    certificate_map_id = "projects/mock-project-id/locations/global/certificateMaps/fn-01-cloud-run-cert-map"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "cloud_armor" {
  config_path = "../../../cloud-armor/cloud-run-lb-policy"
  mock_outputs = {
    policy_self_link = "projects/mock-project-id/global/securityPolicies/fn-01-cloud-run-lb-policy"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "webhook_handler" {
  config_path = "../../cloud-run/webhook-handler"
  mock_outputs = {
    service_name = "fn-01-webhook-handler"
    service_uri  = "https://fn-01-webhook-handler-mock.run.app"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "api_service" {
  config_path = "../../cloud-run/api-service"
  mock_outputs = {
    service_name = "fn-01-api-service"
    service_uri  = "https://fn-01-api-service-mock.run.app"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name = try(dependency.project.outputs.project_name, "fn-01")
}

inputs = {
  project_id = dependency.project.outputs.project_id
  name       = "${local.project_name}-cloud-run-lb"

  address     = dependency.external_ip.outputs.addresses[0]
  enable_ssl  = true
  https_redirect = true

  certificate_map = dependency.cert_map.outputs.certificate_map_id

  backends = {
    "webhook-handler" = {
      groups = [{
        group = dependency.webhook_handler.outputs.service_name
      }]
      path_rules       = ["/webhook/*"]
      security_policy  = dependency.cloud_armor.outputs.policy_self_link
      log_config = {
        enable      = true
        sample_rate = 1.0
      }
      timeout_sec = 30
    }
    "api-service" = {
      groups = [{
        group = dependency.api_service.outputs.service_name
      }]
      path_rules       = ["/api/*"]
      security_policy  = dependency.cloud_armor.outputs.policy_self_link
      log_config = {
        enable      = true
        sample_rate = 1.0
      }
      timeout_sec = 30
    }
  }

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "load-balancer"
      purpose   = "cloud-run-services"
    }
  )
}
