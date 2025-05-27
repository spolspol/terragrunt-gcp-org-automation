# Centralized Provider Versions Configuration
# This file defines all Terraform provider versions used across the infrastructure
# Following the pattern from: https://blog.devgenius.io/using-terragrunt-to-keep-terraform-provider-versions-consistent-e2b2ccd00afe

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.37.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "6.37.0"
    }
  }
}
EOF
}
