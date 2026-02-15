<!-- Space: PE -->
<!-- Title: Certificate Manager Template -->
<!-- Parent: Networking Resources -->
<!-- Label: template -->
<!-- Label: certificate-manager -->
<!-- Label: ssl -->
<!-- Label: tls -->
<!-- Label: security -->
<!-- Label: howto -->
<!-- Label: intermediate -->

# Certificate Manager Template

This document describes the Certificate Manager Terragrunt template for managing SSL/TLS certificates via Google Certificate Authority Service (CAS) with auto-renewal.

## Overview

The Certificate Manager template lives at `_common/templates/certificate_manager.hcl` and uses the [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) `certificate-manager` module v47.0.0. It manages issuance configs, certificates, and certificate maps -- all the resources needed to issue and attach CAS-signed certificates to load balancers.

Key capabilities:
- Private CA-issued certificates via CAS issuance configs
- Auto-renewal with configurable rotation windows
- Certificate maps for load balancer attachment
- Multiple certificates per map (hostname-based routing)

## Template Location

```
_common/templates/certificate_manager.hcl
```

## Module Source

```
git::https://github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-manager?ref=v47.0.0
```

Version pinned in `_common/common.hcl` as `module_versions.certificate_manager`. This is the same Fabric repository as the CAS module.

## Required Inputs

| Input | Type | Description | Example |
|-------|------|-------------|---------|
| `project_id` | string | GCP project ID | `"fn-dev-01-a"` |

## Key Configuration Objects

### Issuance Configs

Issuance configs define how certificates are requested from a CAS CA pool.

| Field | Type | Description |
|-------|------|-------------|
| `ca_pool` | string | Full CAS pool resource path |
| `key_algorithm` | string | Key algorithm -- `ECDSA_P256`, `RSA_2048`, etc. |
| `lifetime` | string | Certificate lifetime (max `"2592000s"` / 30 days for issuance configs) |
| `rotation_window_percentage` | number | Percentage of lifetime at which renewal triggers (recommended: `25`) |

### Certificates

Managed certificates are issued automatically via an issuance config.

| Field | Type | Description |
|-------|------|-------------|
| `managed.domains` | list(string) | Domain names for the certificate |
| `managed.issuance_config` | string | Name of the issuance config to use |

### Certificate Maps

Maps group certificates and route them to load balancer frontends by hostname.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Certificate map name |
| `description` | string | Map description |
| `entries` | map | Hostname-to-certificate mappings |

Each entry:

| Field | Type | Description |
|-------|------|-------------|
| `certificates` | list(string) | Certificate names to attach |
| `hostname` | string | Hostname this entry matches |

## Basic Usage

This example is derived from a real `api-lb-cert` implementation in `fn-dev-01`:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cert_manager_template" {
  path           = "${get_repo_root()}/_common/templates/certificate_manager.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id = "fn-dev-01-a"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "cas" {
  config_path = "${get_repo_root()}/live/non-production/uat/uat-pki/europe-west2/certificate-authority-service/uat-subordinate"
  mock_outputs = {
    ca_pool_id = "projects/uat-pki/locations/europe-west2/caPools/org-uat-pool-01"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  project_id = dependency.project.outputs.project_id

  issuance_configs = {
    fn-dev-01-api-config = {
      ca_pool                    = dependency.cas.outputs.ca_pool_id
      key_algorithm              = "ECDSA_P256"
      lifetime                   = "2592000s" # 30 days (GCP maximum for issuance configs)
      rotation_window_percentage = 25
    }
  }

  certificates = {
    api-fn-dev-01 = {
      managed = {
        domains         = ["api.fn-dev-01.uat.example.io"]
        issuance_config = "fn-dev-01-api-config"
      }
    }
  }

  map = {
    name        = "fn-dev-01-cloud-run-cert-map"
    description = "Certificate map for fn-dev-01 Cloud Run services LB"
    entries = {
      api-fn-dev-01 = {
        certificates = ["api-fn-dev-01"]
        hostname     = "api.fn-dev-01.uat.example.io"
      }
    }
  }
}
```

## Common Patterns

### CAS-Issued Certificate for Load Balancer

The primary pattern: issue a private CA certificate via CAS and attach it to an HTTPS load balancer through a certificate map.

```
Root CA (dev-pki)
  └── Subordinate CA (uat-subordinate in org-uat-pool-01)
        └── Issuance Config (fn-dev-01-api-config)
              └── Certificate (api-fn-dev-01)
                    └── Certificate Map (fn-dev-01-cloud-run-cert-map)
                          └── Load Balancer frontend
```

The load balancer references the map via its `certificate_map` input:

```hcl
# In the load balancer terragrunt.hcl
dependency "cert_manager" {
  config_path = "../../certificate-manager/api-lb-cert"
  mock_outputs = {
    map_id = "projects/mock-project-id/locations/global/certificateMaps/mock-cert-map"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  ssl             = true
  certificate_map = dependency.cert_manager.outputs.map_id
}
```

### Multiple Certificates per Map

Add additional entries when a single load balancer serves multiple hostnames:

```hcl
inputs = {
  certificates = {
    api-cert = {
      managed = {
        domains         = ["api.example.com"]
        issuance_config = "my-issuance-config"
      }
    }
    admin-cert = {
      managed = {
        domains         = ["admin.example.com"]
        issuance_config = "my-issuance-config"
      }
    }
  }

  map = {
    name = "multi-host-cert-map"
    entries = {
      api = {
        certificates = ["api-cert"]
        hostname     = "api.example.com"
      }
      admin = {
        certificates = ["admin-cert"]
        hostname     = "admin.example.com"
      }
    }
  }
}
```

## Dependencies

| Dependency | Required | Description |
|------------|----------|-------------|
| CAS CA pool | Yes | A subordinate CA pool must exist (e.g. `uat-pki/org-uat-pool-01`) |
| Certificate Manager API | Yes | Must be enabled on the target project |
| Certificate Manager service agent | Yes | Must be provisioned and granted `privateca.certificateRequester` on the CA pool |
| Load balancer | No | Required only if attaching certificates via a map |

### Cross-Project IAM for CAS Pools

When the Certificate Manager and CAS pool live in **different projects** (e.g. certificates in `fn-dev-01`, CA pool in `uat-pki`), two additional steps are required:

**1. Provision the Certificate Manager service agent** in the consuming project via `activate_api_identities` in the project factory module:

```hcl
# In the consuming project's terragrunt.hcl (e.g. fn-dev-01/project/)
inputs = {
  activate_api_identities = [
    {
      api   = "certificatemanager.googleapis.com"
      roles = []
    }
  ]
}
```

This creates `service-<PROJECT_NUMBER>@gcp-sa-certificatemanager.iam.gserviceaccount.com`.

**2. Grant the service agent access** to the CAS pool via the `iam` input on the CAS module:

```hcl
# In the CAS subordinate terragrunt.hcl (e.g. uat-pki/.../uat-subordinate/)
inputs = {
  iam = {
    "roles/privateca.certificateRequester" = [
      "group:gg_org-devops@example.com",
      "serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-certificatemanager.iam.gserviceaccount.com",
    ]
  }
}
```

Without both steps, certificates will remain stuck in `PROVISIONING` with `AUTHORIZATION_ISSUE`.

The CAS CA hierarchy for the current UAT environment:

```
Root CA (dev-pki project)
  └── Subordinate CA (uat-pki project, org-uat-pool-01)
        ├── IAM: gg_org-devops (certificateRequester)
        └── IAM: service-<PROJECT_NUMBER> (certificateRequester) <- fn-dev-01 CM agent
```

## CI/CD Integration

| Setting | Value |
|---------|-------|
| Resource type | `certificate-manager` |
| Dependencies | `projects`, `certificate-authority-service` |
| Path pattern | `live/**/certificate-manager/**` |
| Config file | `.github/workflow-config/resource-definitions.yml` |

The resource is automatically detected and deployed by the IaC Engine workflow when changes are merged to `main`.

## Best Practices

- Use **ECDSA_P256** for key algorithm -- better performance than RSA for TLS handshakes.
- Set **rotation window to 25%** to allow adequate time for renewal and propagation.
- Keep **lifetime at 30 days maximum** (`2592000s`) -- this is the GCP limit for issuance configs and follows short-lived certificate best practice.
- Always chain through a **subordinate CA**, never issue directly from the root CA.
- Use **certificate maps** (not direct SSL certificate references) for load balancer attachment -- maps allow zero-downtime certificate rotation.
- Name certificates and map entries consistently to aid debugging.

## Troubleshooting

### Certificate Not Issuing

**Symptom**: Certificate stays in `PENDING` state.

**Common causes**:
1. CAS pool permissions -- the Certificate Manager service agent needs `privateca.certificateRequester` on the CA pool.
2. Issuance config references a non-existent CA pool path.
3. Certificate Manager API not enabled on the project.

```bash
# Check certificate status
gcloud certificate-manager certificates describe api-fn-dev-01 \
  --project=fn-dev-01-a

# Verify CA pool permissions
gcloud privateca pools get-iam-policy org-uat-pool-01 \
  --location=europe-west2 \
  --project=uat-pki
```

### Map Not Attaching to Load Balancer

**Symptom**: LB returns default certificate or SSL errors.

**Common causes**:
1. The `map_id` output format must match what the LB module expects.
2. Hostname in the map entry does not match the DNS record pointing to the LB.

```bash
# Verify map exists
gcloud certificate-manager maps describe fn-dev-01-cloud-run-cert-map \
  --project=fn-dev-01-a

# List map entries
gcloud certificate-manager maps entries list \
  --map=fn-dev-01-cloud-run-cert-map \
  --project=fn-dev-01-a
```

## References

- [Certificate Manager documentation](https://cloud.google.com/certificate-manager/docs)
- [Cloud Foundation Fabric certificate-manager module](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/certificate-manager)
- [Certificate Authority Service documentation](https://cloud.google.com/certificate-authority-service/docs)
- [Configuration Templates Overview](CONFIGURATION_TEMPLATES.md)
