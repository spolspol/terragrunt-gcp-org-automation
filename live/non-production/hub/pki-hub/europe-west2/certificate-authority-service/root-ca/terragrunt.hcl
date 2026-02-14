include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cas_template" {
  path           = "${get_repo_root()}/_common/templates/certificate_authority_service.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id = "org-pki-hub"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "crl_bucket" {
  config_path = "../../buckets/pki-crl"
  mock_outputs = {
    names = {
      "org-pki-crl" = "org-pki-crl"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  bucket_name  = "org-pki-crl"
  ca_pool_name = "org-root-pool-01"
  ca_name      = "org-root-ca-01"
}

inputs = {
  project_id = dependency.project.outputs.project_id
  location   = "europe-west2"
  ca_pool_config = {
    create_pool = {
      name            = local.ca_pool_name
      enterprise_tier = false
    }
  }

  ca_configs = {
    (local.ca_name) = {
      is_self_signed = true
      lifetime       = "315360000s" # 10 years
      gcs_bucket     = try(dependency.crl_bucket.outputs.names[local.bucket_name], local.bucket_name)
      labels = {
        environment = "hub"
        scope       = "root"
        managed_by  = "terragrunt"
      }
      subject = {
        common_name         = "Example Org Root CA"
        organization        = "Example Organisation"
        organizational_unit = "Operations"
        country_code        = "GB"
        province            = "London"
        locality            = "London"
      }
      key_spec = {
        algorithm = "RSA_PKCS1_4096_SHA256"
      }
      key_usage = {
        cert_sign          = true
        client_auth        = false
        code_signing       = false
        content_commitment = false
        crl_sign           = true
        data_encipherment  = false
        decipher_only      = false
        digital_signature  = false
        email_protection   = false
        encipher_only      = false
        key_agreement      = false
        key_encipherment   = false
        ocsp_signing       = false
        server_auth        = false
        time_stamping      = false
      }
    }
  }

  iam_by_principals = {
    "group:gg_org-devops@example.com" = [
      "roles/privateca.admin"
    ]
  }
}
