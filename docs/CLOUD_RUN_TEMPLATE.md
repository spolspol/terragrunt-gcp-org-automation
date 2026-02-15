<!-- Space: PE -->
<!-- Title: Cloud Run Template -->
<!-- Parent: Compute Resources -->
<!-- Label: template -->
<!-- Label: cloud-run -->
<!-- Label: serverless -->
<!-- Label: howto -->
<!-- Label: intermediate -->

# Cloud Run Template

This document describes the Cloud Run Terragrunt template for deploying Cloud Run services consistently across environments.

## Overview

The Cloud Run template lives at `_common/templates/cloud-run.hcl` and uses the official `GoogleCloudPlatform/terraform-google-cloud-run` module (v2 submodule). It provides standardized defaults for security, scaling, and labels while keeping service-specific configuration in each Cloud Run unit.

## Defaults

The template sets these defaults unless overridden in a service:

- **Ingress**: `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` (internal + Cloud Load Balancer only)
- **Scaling**: `min_instance_count = 0`, `max_instance_count = 10`
- **Concurrency**: `max_instance_request_concurrency = "80"`
- **Timeout**: `"300s"`
- **Service account**: created by default (`create_service_account = true`)
- **Labels**: `managed_by = "terragrunt"`, `component = "cloud-run"` merged with common tags

## Required Inputs

| Input | Description | Example |
| --- | --- | --- |
| `project_id` | GCP project ID | `dp-dev-01` |
| `location` | Cloud Run region | `europe-west2` |
| `service_name` | Cloud Run service name | `hello-cloud-run` |
| `containers` | Container definitions (list) | See example below |

## Basic Usage

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_run_template" {
  path           = "${get_repo_root()}/_common/templates/cloud-run.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../example-project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Only resource-specific overrides needed -- template defaults auto-merged
inputs = {
  project_id   = dependency.project.outputs.project_id
  location     = include.base.locals.region
  service_name = "hello-cloud-run"

  containers = [
    {
      container_image = "gcr.io/cloudrun/hello"
      ports = {
        container_port = 8080
      }
    }
  ]

  members = []
}
```

## Common Patterns

### Internal Service (Default)
- Keep `ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"`
- Do not add `allUsers` to `members`
- Use a VPC connector or direct VPC egress only if needed

### Public Service (Explicit)
```hcl
inputs = {
  ingress = "INGRESS_TRAFFIC_ALL"
  members = ["allUsers"]
}
```
Use `allAuthenticatedUsers` if you want any Google-authenticated identity instead of full public access.

### VPC Access via Connector (Legacy)

> **Note:** Direct VPC Egress (see below) is the recommended approach. VPC Connectors have scaling limitations and are being superseded by network interfaces.

```hcl
inputs = {
  vpc_access = {
    connector = "projects/PROJECT/locations/REGION/connectors/CONNECTOR"
    egress    = "PRIVATE_RANGES_ONLY"
  }
}
```

### Secrets via Secret Manager

```hcl
inputs = {
  containers = [
    {
      container_image = "gcr.io/cloudrun/hello"
      env_secret_vars = {
        DATABASE_PASSWORD = {
          secret  = "db-password"  #pragma: allowlist secret
          version = "latest"
        }
      }
    }
  ]
}
```

### VPC Direct Egress (Cloud NAT Routing)

Route all egress through the project VPC and Cloud NAT for static IP egress. This avoids VPC Connector scaling limits and is the recommended approach for Cloud Run services that need deterministic outbound IPs.

```hcl
inputs = {
  vpc_access = {
    network_interfaces = {
      network    = dependency.vpc_network.outputs.network_name
      subnetwork = "projects/${local.project_id}/regions/${local.region}/subnetworks/${local.subnet_name}"
      tags       = ["cloud-run-direct-vpc"]
    }
    egress = "ALL_TRAFFIC"
  }
}
```

### Shared Service Account

Use when multiple Cloud Run services share the same identity and permissions. Disable per-service SA creation and reference a shared SA deployed separately.

```hcl
inputs = {
  create_service_account = false
  service_account        = dependency.shared_sa.outputs.email
}
```

### Cloud SQL via Proxy Socket

Connect to Cloud SQL using the built-in Cloud SQL Auth Proxy sidecar. Pass the instance connection name as `DB_HOST` and inject the password from Secret Manager.

```hcl
inputs = {
  containers = [
    {
      container_image = "gcr.io/my-project/my-app:latest"
      env_vars = {
        DB_HOST = "/cloudsql/${local.project_id}:${local.region}:${local.instance_name}"
      }
      env_secret_vars = {
        DB_PASSWORD = {
          secret  = "db-password"  #pragma: allowlist secret
          version = "latest"
        }
      }
    }
  ]
}
```

## Best Practices

- Keep ingress internal by default and explicitly opt into public exposure.
- Use least-privilege service accounts and limit IAM invokers to required identities.
- Cap max instances to control cost and avoid runaway scaling.
- Document service-specific overrides in the service `terragrunt.hcl`.
- Validate VPC access configuration and ensure connectors exist before applying.
- Use Direct VPC Egress over VPC Connector for Cloud NAT routing (avoids connector scaling limits).
