# Certificate Manager - managed certificate via private CA
# Issues certificates from the PKI hub's Certificate Authority Service

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "certificate_manager_template" {
  path           = "${get_repo_root()}/_common/templates/certificate_manager.hcl"
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

locals {
  project_name = try(dependency.project.outputs.project_name, "dev-01")
  cert_domain  = "api.${local.project_name}.dev.example.io"

  # CA Pool reference from PKI hub (update with actual values)
  ca_pool_id = "projects/org-pki-hub/locations/${include.base.locals.region}/caPools/dev-subordinate"
}

inputs = {
  project_id = dependency.project.outputs.project_id

  # Certificate issuance configuration
  issuance_config = {
    name        = "${local.project_name}-api-config"
    description = "Issuance config for ${local.cert_domain}"
    ca_pool     = local.ca_pool_id
    key_algorithm          = "ECDSA_P256"
    lifetime               = "2592000s" # 30 days
    rotation_window_percentage = 25
  }

  # Managed certificate
  certificates = {
    "${local.project_name}-api-cert" = {
      description = "TLS certificate for ${local.cert_domain}"
      domains     = [local.cert_domain]
    }
  }

  # Certificate map for load balancer
  certificate_map = {
    name        = "${local.project_name}-cert-map"
    description = "Certificate map for ${local.project_name} load balancer"
    entries = {
      "api" = {
        hostname = local.cert_domain
      }
    }
  }

  # Labels
  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "certificate-manager"
      purpose   = "api-tls"
    }
  )
}
