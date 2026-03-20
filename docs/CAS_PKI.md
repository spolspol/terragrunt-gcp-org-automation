# Certificate Authority Service (CAS) -- PKI Implementation

The organisation runs a hierarchical private PKI on Google Certificate Authority Service (CAS). A single Root CA lives in the central `pki-hub` project; environment-specific subordinate CAs live in their own projects. Automation uses the Cloud Foundation Fabric `certificate-authority-service` module (v47.0.0).

## Overview

| Attribute | Value |
|-----------|-------|
| Region | `europe-west2` |
| Root project | `pki-hub` (ID: `org-pki-hub`) |
| Module | `GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-authority-service` |
| Version | v47.0.0 (pinned in `_common/common.hcl`) |
| Template | `_common/templates/certificate_authority_service.hcl` |
| Cert Manager template | `_common/templates/certificate_manager.hcl` (same Fabric repo, v47.0.0) |
| CRL publishing | GCS bucket `gs://org-pki-crl` in `pki-hub` |

## Certificate Hierarchy

```
Organisation Root CA  (pki-hub, RSA 4096, 10-year lifetime)
├── Development Subordinate CA  (dev-pki, RSA 4096, 5-year, constrained to .dev.example.io)
└── UAT Subordinate CA          (uat-pki, RSA 4096, 5-year, constrained to UAT domains)
```

The Fabric module wires `subordinate_config.root_ca_id` to the hub CA, so subordinates activate automatically once the root exists. Manual CSR signing is only needed for out-of-band scenarios (e.g., an external root CA).

## Directory Structure

```
live/non-production/hub/pki-hub/
├── project/
└── europe-west2/
    ├── buckets/pki-crl/                            # CRL publishing bucket
    └── certificate-authority-service/
        └── root-ca/                                # Root CA pool + authority

live/non-production/development/dev-pki/
├── project/
└── europe-west2/
    ├── buckets/dev-pki-crl/
    └── certificate-authority-service/
        └── dev-subordinate/                        # Dev subordinate CA

live/non-production/uat/uat-pki/
├── project/
└── europe-west2/
    ├── buckets/uat-pki-crl/
    └── certificate-authority-service/
        └── uat-subordinate/                        # UAT subordinate CA
```

## Configuration

### IAM Model

| CA Pool | Principal | Role |
|---------|-----------|------|
| Root (pki-hub) | `group:ggg_pki-admins@example.com` | `roles/privateca.admin` |
| Dev (dev-pki) | `group:ggg_dev-ops@example.com` | `roles/privateca.certificateRequester` |
| UAT (uat-pki) | `group:gg_org-devops@example.com` | `roles/privateca.certificateRequester` |

Grant `roles/privateca.certificateManager` to automation identities that need certificate lifecycle management.

### Cloud SQL Integration

Cloud SQL can use CAS-managed server certificates, but this requires `ENTERPRISE_PLUS` edition. For cost-sensitive environments, use Google-managed CA with `ENCRYPTED_ONLY` SSL mode instead.

```hcl
# ENTERPRISE_PLUS only
ip_configuration = {
  server_ca_mode = "CUSTOMER_MANAGED_CAS_CA"
  server_ca_pool = "projects/uat-pki/locations/europe-west2/caPools/org-uat-pool-01"
  ssl_mode       = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"
}
```

The Cloud SQL service agent needs `roles/privateca.certificateRequester` on the PKI project.

### Certificate Manager Integration

The `_common/templates/certificate_manager.hcl` template wraps the Fabric `certificate-manager` module for managing certificates, maps, and DNS authorisations. Live resources are at paths like `live/non-production/development/functions/fn-dev-01/europe-west2/certificate-manager/`.

## Usage

### Prerequisites

PKI project configurations include an `after_hook` that runs `gcloud beta services identity create --service=privateca.googleapis.com` automatically. No manual step is needed.

```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json
```

### Deploy Order

Deploy resources sequentially, committing and pushing between steps:

```bash
# 1. Hub project + CRL bucket + Root CA
cd live/non-production/hub/pki-hub/project
terragrunt plan && terragrunt apply -auto-approve

cd ../europe-west2/buckets/pki-crl
terragrunt plan && terragrunt apply -auto-approve

cd ../certificate-authority-service/root-ca
terragrunt plan && terragrunt apply -auto-approve

# 2. Dev subordinate (project + CRL bucket + CA)
cd ../../../../development/dev-pki/project
terragrunt plan && terragrunt apply -auto-approve

cd ../europe-west2/buckets/dev-pki-crl
terragrunt plan && terragrunt apply -auto-approve

cd ../certificate-authority-service/dev-subordinate
terragrunt plan && terragrunt apply -auto-approve

# 3. UAT subordinate (same pattern)
cd live/non-production/uat/uat-pki/project
terragrunt plan && terragrunt apply -auto-approve
# ... buckets, then certificate-authority-service
```

### Manual Subordinate Signing (Optional)

Only needed when exchanging CSRs with an external CA:

1. Deploy the subordinate CA (creates CSR, CA remains pending)
2. Extract CSR: `terragrunt output --json | jq -r '.cas["org-dev-subordinate-ca"].pem_csr' > dev-sub.csr`
3. Sign with root: `gcloud privateca certificates create ... --csr=dev-sub.csr`
4. Feed signed cert back via `activate_config` block and reapply

## Troubleshooting

- **CAS service identity missing** -- run `gcloud beta services identity create --service=privateca.googleapis.com --project=PROJECT_ID` (normally handled by the project `after_hook`).
- **Subordinate stuck in PENDING** -- verify the root CA exists and `subordinate_config.root_ca_id` points to it.
- **OpenTofu version constraint** -- CAS module requires >= 1.10.0.
- **Change not detected in CI** -- validate the path matches `live/**/certificate-authority-service/*/`.

## References

- [Cloud Foundation Fabric CAS module (v47.0.0)](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/certificate-authority-service)
- [Google CAS product docs](https://cloud.google.com/certificate-authority-service)
- [Customer-managed CA for Cloud SQL](https://cloud.google.com/sql/docs/postgres/customer-managed-ca)
- [Cloud SQL PostgreSQL Template](CLOUD_SQL_POSTGRES_TEMPLATE.md)
