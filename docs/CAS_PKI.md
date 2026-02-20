<!-- Space: PE -->
<!-- Title: CAS PKI Implementation -->
<!-- Parent: Foundation Resources -->
<!-- Label: pki -->
<!-- Label: cas -->
<!-- Label: certificate-authority -->
<!-- Label: security -->
<!-- Label: foundation -->

# Certificate Authority Service (CAS) -- PKI Implementation

## Overview

The organization operates a hierarchical private PKI on Google Certificate Authority Service (CAS). The design uses a single organization Root CA in a central hub project and environment-specific subordinate CAs in their own projects. Automation is implemented with Terragrunt + OpenTofu and Google's Cloud Foundation Fabric module `modules/certificate-authority-service` (v47.0.0).

- Region: `europe-west2` (regional CAS)
- Root project: `pki-hub` (ID: `org-pki-hub`)
- Dev PKI project: `dev-pki` (ID: `dev-pki`)
- UAT PKI project: `uat-pki` (ID: `uat-pki`)
- CRL publishing: GCS bucket `gs://org-pki-crl` in `pki-hub`
- Module source: `git::https://github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-authority-service?ref=v47.0.0`

## Certificate Hierarchy

- Organization Root CA
  - CN: Organization Root CA
  - Subject: O=Example Organization, OU=Operations, C=GB
  - Key: RSA 4096, Lifetime: 10 years

- Development Subordinate CA
  - CN: Organization Dev Subordinate CA
  - Subject: O=Example Organization, OU=Development, C=GB
  - Key: RSA 4096, Lifetime: 5 years
  - Issuance policy constrained for development domains (e.g., `.dev.example.io`)

- UAT Subordinate CA
  - CN: Organization UAT Subordinate CA
  - Subject: O=Example Organization, OU=UAT, C=GB
  - Key: RSA 4096, Lifetime: 5 years
  - Issuance policy constrained for UAT domains

## Repository Layout

```
live/non-production/hub/pki-hub/
├── project/                                      # Project factory
└── europe-west2/
    ├── buckets/pki-crl/                          # org-pki-crl (CRL publishing)
    └── certificate-authority-service/
        └── root-ca/                              # Root CA pool + authority

live/non-production/development/dev-pki/
├── project/                                      # Dev PKI project
└── europe-west2/
    ├── buckets/dev-pki-crl/                     # dev-pki-crl (CRL publishing)
    └── certificate-authority-service/
        └── dev-subordinate/                      # Dev CA pool + subordinate CA

live/non-production/uat/uat-pki/
├── project/                                      # UAT PKI project
└── europe-west2/
    ├── buckets/uat-pki-crl/                     # uat-pki-crl (CRL publishing)
    └── certificate-authority-service/
        └── uat-subordinate/                     # UAT CA pool + subordinate CA
```

Terragrunt template: `_common/templates/certificate_authority_service.hcl` wires inputs to the Google-maintained module. Versions are centralized in `_common/common.hcl` (`module_versions.certificate_authority_service`).

## IAM Model

- Root CA Pool/CA (pki-hub): `group:ggg_pki-admins@example.com` -> `roles/privateca.admin`
- Dev Pool/CA (dev-pki): `group:ggg_dev-ops@example.com` -> `roles/privateca.certificateRequester`
- UAT Pool/CA (uat-pki): `group:gg_org-devops@example.com` -> `roles/privateca.certificateRequester`

Grant additional roles (e.g., `roles/privateca.certificateManager`) to automation identities as needed for certificate lifecycle.

## Deploy Order (Terragrunt)

Authenticate and set environment (see README quick start), then:

1) Hub project
- `cd live/non-production/hub/pki-hub/project`
- `terragrunt run plan && terragrunt run apply`

2) CRL bucket
- `cd ../europe-west2/buckets/pki-crl`
- `terragrunt run plan && terragrunt run apply`

3) Root CA pool + CA
- `cd ../certificate-authority-service/root-ca`
- `terragrunt run plan && terragrunt run apply`

4) Dev project
- `cd ../../../../development/dev-pki/project`
- `terragrunt run plan && terragrunt run apply`

5) Dev CRL bucket
- `cd ../europe-west2/buckets/dev-pki-crl`
- `terragrunt run plan && terragrunt run apply`

6) Dev subordinate CA pool + CA
- `cd ../certificate-authority-service/dev-subordinate`
- `terragrunt run plan && terragrunt run apply`

7) UAT PKI project
- `cd live/non-production/uat/uat-pki/project`
- `terragrunt run plan && terragrunt run apply`

8) UAT CRL bucket
- `cd ../europe-west2/buckets/uat-pki-crl`
- `terragrunt run plan && terragrunt run apply`

9) UAT subordinate CA pool + CA
- `cd ../certificate-authority-service/uat-subordinate`
- `terragrunt run plan && terragrunt run apply`

### Bootstrap prerequisites

**CAS Service Identity (Automated)**: PKI project configurations include a Terragrunt `after_hook` that automatically runs `gcloud beta services identity create --service=privateca.googleapis.com` after each project apply. This eliminates the need to manually create CAS service identities - the hook is idempotent and safe to run multiple times.

Before running the Terragrunt steps above, ensure authentication is configured:

```bash
# Authenticate with the org-level service account
export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json
gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"

# (Optional) confirm state bucket access works before Terragrunt
gsutil ls gs://org-tofu-state
```

After the projects exist you can deploy each component with `terragrunt run apply -auto-approve` following the order above. When state access is unavailable (e.g., bootstrap laptop), temporarily rely on `mock_outputs` but always rerun Terragrunt once state access is restored.

> **Note**: If you need to manually create a CAS service identity (e.g., for a non-PKI project), use:
> ```bash
> gcloud beta services identity create \
>   --service=privateca.googleapis.com \
>   --project=PROJECT_ID
> ```

## Subordinate Activation Flow

Subordinate CAs must be signed by their parent (the root). The Fabric module we use wires `subordinate_config.root_ca_id` directly to the hub CA, so Terragrunt automatically activates the subordinate as soon as the root CA exists--no manual signing required. Only follow the CSR-first flow below if you need to do an out-of-band signing (for example, when exchanging CSRs with an external CA).

### Manual signing procedure (optional)

1. **Deploy the subordinate CA in "pending activation"**
   ```bash
   cd live/non-production/development/dev-pki/europe-west2/certificate-authority-service/dev-subordinate
   terragrunt run apply -auto-approve   # produces CSR, CA is pending
   ```

2. **Capture the CSR that the Fabric module outputs**
   ```bash
   terragrunt output --json \
     | jq -r '.cas["org-dev-subordinate-ca"].pem_csr' \
     > dev-subordinate.csr
   ```
   (The `cas` output map is keyed by CA name; update the key if you change `local.ca_name`.)

3. **Use the root CA to sign the CSR**
   ```bash
   ROOT_CA_ID=$(cd ../../../hub/pki-hub/europe-west2/certificate-authority-service/root-ca \
     && terragrunt output --json \
     | jq -r '.ca_ids["org-root-ca-00"]')

   gcloud privateca certificates create dev-subordinate-activation \
     --issuer="${ROOT_CA_ID}" \
     --csr=dev-subordinate.csr \
     --cert-output-file=dev-subordinate.pem \
     --chain-output-file=dev-subordinate-chain.pem \
     --use-csr=true \
     --project=org-pki-hub \
     --location=europe-west2 \
     --pool=org-root-pool-00
   ```

4. **Feed the signed certificate back into the subordinate module**
   Update `ca_configs.org-dev-subordinate-ca` with an `activate_config` block (or temporarily inject via `TF_VAR_` env vars) and reapply:
   ```hcl
   activate_config = {
     pem_ca_certificate   = file("dev-subordinate.pem")
     pem_ca_cert_chain    = file("dev-subordinate-chain.pem")
   }
   ```
   Then rerun `terragrunt run apply -auto-approve`. The subordinate transitions to `ACTIVE` and CRLs begin publishing to the dev CRL bucket.

5. **Verify**
   ```bash
   gcloud privateca certificate-authorities describe \
     projects/dev-pki/locations/europe-west2/caPools/org-dev-pool/certificateAuthorities/org-dev-subordinate-ca \
     --format='value(state)'

   gcloud storage ls gs://<actual-dev-pki-crl-bucket-name>
   ```

After activation, end-entity issuance from the dev pool will chain to the root CA and publish CRLs to `org-pki-crl`.

## CI/CD Integration

- PR and Apply engines detect and process CAS resources (`certificate-authority-service`):
  - Paths: `live/**/certificate-authority-service/*/` and `_common/templates/certificate_authority_service.hcl`
  - Template changes trigger all CAS resources in live/non-production/
  - Aggregated folders (e.g., `.../certificate-authority-service`) expand to child directories with `terragrunt.hcl`
- Reusable detector: `.github/scripts/detect-resource-changes.sh`

## Operations

- Rollovers: Create a new CA in the pool and transition issuance; keep CRLs available during overlap
- CRL hygiene: Bucket has a 90-day delete rule; adjust per compliance
- Audit: Ensure audit logging on projects and review CAS access logs

## Cloud SQL Integration

Cloud SQL PostgreSQL instances can use customer-managed CA from CAS for server certificates, providing centralised certificate management across environments.

### Edition Requirements

**Important:** Customer-managed CA (`CUSTOMER_MANAGED_CAS_CA`) requires `ENTERPRISE_PLUS` edition:

| Edition | Compatible Tiers | Customer-Managed CA |
|---------|-----------------|---------------------|
| ENTERPRISE | db-f1-micro, db-g1-small, db-n1-* | Not supported |
| ENTERPRISE_PLUS | db-perf-optimized-N-* | Supported |

For cost-sensitive environments, use Google-managed CA with `ENCRYPTED_ONLY` SSL mode instead.

### Configuration (ENTERPRISE_PLUS only)

Set `server_ca_mode = "CUSTOMER_MANAGED_CAS_CA"` in the Cloud SQL ip_configuration:

```hcl
ip_configuration = {
  server_ca_mode = "CUSTOMER_MANAGED_CAS_CA"
  server_ca_pool = "projects/uat-pki/locations/europe-west2/caPools/org-uat-pool-01"
  ssl_mode = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"
}
```

### IAM Requirements

Grant `roles/privateca.certificateRequester` to the Cloud SQL service agent on the PKI project where the CA pool resides:

```hcl
# In <pki-project>/iam-bindings/terragrunt.hcl
service_account_roles = {
  "serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-cloud-sql.iam.gserviceaccount.com" = [
    "roles/privateca.certificateRequester",
  ]
}
```

### Current Deployments

| Cloud SQL Instance | Edition | CA Type | Notes |
|--------------------|---------|---------|-------|
| dp-dev-01-postgres-main | ENTERPRISE | Google-managed | Cost optimisation (~$15/month) |

> **Note:** The UAT Cloud SQL instance was originally planned to use customer-managed CA from `org-uat-pool-01`, but switched to Google-managed CA due to ENTERPRISE_PLUS edition cost (~$200+/month).

### Certificate Flow (Customer-Managed)

When using customer-managed CA with ENTERPRISE_PLUS:

1. Cloud SQL instance is created with `CUSTOMER_MANAGED_CAS_CA` mode
2. Cloud SQL service agent requests server certificate from specified CA pool
3. CAS issues certificate signed by the subordinate CA
4. Server presents certificate chain (subordinate -> root) to clients
5. Clients verify chain against stored CA certificates

### Verification

```bash
# Verify Cloud SQL instance CA configuration
gcloud sql instances describe <instance-name> --project=<project-id> \
  --format="yaml(settings.ipConfiguration.serverCaMode,settings.ipConfiguration.serverCaPool,settings.ipConfiguration.sslMode)"

# Verify IAM on CA pool (if using customer-managed CA)
gcloud privateca pools get-iam-policy <ca-pool> \
  --project=<pki-project> \
  --location=<region>
```

## Troubleshooting

- OpenTofu version must satisfy module constraint (>= 1.10.0). CI defaults to `1.10.7` (configurable)
- Terragrunt must be `>= 0.93.x` for complex dependency graphs; CI defaults to `0.93.3`
- "dependency not defined in locals": Avoid referencing `dependency.*` in `locals`; read dependency outputs directly where used
- Resource detection: If a CAS change isn't picked up, validate the path matches `live/**/certificate-authority-service/*/`

## References

- Cloud Foundation Fabric CAS module: modules/certificate-authority-service (v47.0.0)
- Google CAS product docs: https://cloud.google.com/certificate-authority-service
- Customer-managed CA for Cloud SQL: https://cloud.google.com/sql/docs/postgres/customer-managed-ca
- Terragrunt docs: https://terragrunt.gruntwork.io
- OpenTofu docs: https://opentofu.org
- [Cloud SQL PostgreSQL Template](CLOUD_SQL_POSTGRES_TEMPLATE.md)
