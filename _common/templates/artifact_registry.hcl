# Artifact Registry Template
# This template provides standardized Artifact Registry configuration
# Include this template in your Terragrunt configurations for consistent repository setups

terraform {
  source = "git::https://github.com/GoogleCloudPlatform/terraform-google-artifact-registry.git//?ref=${local.module_versions.artifact_registry}"
}

locals {
  # Get module versions from common configuration
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions

  # Default repository configuration
  default_config = {
    location       = "europe-west2"
    format         = "DOCKER"
    mode           = "STANDARD_REPOSITORY"
    description    = ""
    immutable_tags = false
  }

  # Environment-specific settings
  env_configs = {
    production = {
      immutable_tags = true
      cleanup_policies = {
        keep-tagged = {
          action = "KEEP"
          condition = {
            tag_state = "TAGGED"
          }
        }
        delete-untagged = {
          action = "DELETE"
          condition = {
            tag_state  = "UNTAGGED"
            older_than = "604800s" # 7 days
          }
        }
      }
    }
    non-production = {
      immutable_tags = false
      cleanup_policies = {
        delete-old-untagged = {
          action = "DELETE"
          condition = {
            tag_state  = "UNTAGGED"
            older_than = "86400s" # 1 day
          }
        }
      }
    }
  }

  # Standard format configurations
  format_configs = {
    docker = {
      format = "DOCKER"
      docker_config = {
        immutable_tags = false
      }
    }
    npm = {
      format = "NPM"
    }
    python = {
      format = "PYTHON"
    }
    maven = {
      format = "MAVEN"
      maven_config = {
        allow_snapshot_overwrites = false
        version_policy            = "VERSION_POLICY_UNSPECIFIED"
      }
    }
    apt = {
      format = "APT"
    }
    yum = {
      format = "YUM"
    }
    go = {
      format = "GO"
    }
  }
}

# Default inputs - these will be merged with specific configurations
inputs = {
  # Required parameters - must be provided in specific implementations
  project_id    = null # Must be provided
  repository_id = null # Must be provided

  # Location and format configuration
  location = local.default_config.location
  format   = local.default_config.format

  # Repository mode (STANDARD_REPOSITORY, VIRTUAL_REPOSITORY, REMOTE_REPOSITORY)
  mode = local.default_config.mode

  # Optional description
  description = local.default_config.description

  # Docker-specific configuration
  docker_config = null

  # Maven-specific configuration
  maven_config = null

  # Remote repository configuration (for REMOTE_REPOSITORY mode)
  remote_repository_config = null

  # Virtual repository configuration (for VIRTUAL_REPOSITORY mode)
  virtual_repository_config = null

  # IAM members for repository access
  # Format: { readers = [...], writers = [...] }
  members = {}

  # Cleanup policies for automatic artifact deletion
  cleanup_policies = {}

  # Whether to run cleanup in dry-run mode
  cleanup_policy_dry_run = false

  # KMS key for encryption (optional)
  kms_key_name = null

  # Labels
  labels = {
    managed_by = "terragrunt"
    component  = "artifact-registry"
  }
}
