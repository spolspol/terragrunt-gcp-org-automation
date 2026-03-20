# GCP Bootstrap Process

The bootstrap script creates the foundational GCP resources that all subsequent Terragrunt-managed infrastructure depends on: a service account with organisation-level permissions, a state bucket, and a billing-reports bucket. Without these, no other resource in this repository can be planned or applied.

## What the Bootstrap Creates

1. **GCP Folder**: `org-bootstrap` folder under the organisation
2. **GCP Project**: `org-automation` project within the bootstrap folder
3. **Service Account**: `tofu-sa-org` with organisation-level permissions
4. **Service Account Key**: Saved to `$HOME/tofu-sa-org-key.json`
5. **GCS Bucket**: `org-tofu-state` for Terragrunt remote state
6. **Billing Bucket**: `org-billing-usage-reports` for centralised billing data
7. **Helper Script**: `scripts/apply-project-permissions.sh` for new projects

## Usage

```bash
# Interactive (prompts for org and billing)
./scripts/org-bootstrap.sh

# Explicit parameters
./scripts/org-bootstrap.sh [ORG_ID] [BILLING_ACCOUNT]
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ORG_ID` | `YOUR_ORG_ID` | GCP Organisation ID |
| `BILLING_ACCOUNT` | `YOUR_BILLING_ACCOUNT` | Billing Account ID |

## Prerequisites

1. **GCP Authentication**: `gcloud auth login`
2. **Required APIs** (enabled in the current project):
   - `cloudresourcemanager.googleapis.com`
   - `cloudbilling.googleapis.com`
   - `storage.googleapis.com`
   - `iam.googleapis.com`
   - `serviceusage.googleapis.com`
3. **Permissions**: Your account needs organisation-level access to create folders, projects, service accounts, and manage billing

## Bootstrap Phases

### Phase 1 -- Service Account
Creates `tofu-sa-org` in the current project and saves the key to `$HOME/tofu-sa-org-key.json`.

### Phase 2 -- Organisation Permissions
Grants the service account these organisation-level roles:

- `roles/resourcemanager.folderAdmin`
- `roles/resourcemanager.projectCreator`
- `roles/resourcemanager.projectDeleter`
- `roles/resourcemanager.projectIamAdmin`
- `roles/billing.user`
- `roles/resourcemanager.organizationAdmin`
- `roles/securitycenter.adminEditor`
- `roles/essentialcontacts.admin`

### Phase 3 -- GCP Infrastructure
Using the service account:

1. Creates `org-bootstrap` folder under the organisation
2. Creates `org-automation` project in that folder
3. Links billing account to project
4. Enables required APIs
5. Creates `org-tofu-state` GCS bucket (versioned, uniform access)
6. Creates `org-billing-usage-reports` GCS bucket (versioned, uniform access)

### Phase 4 -- Project Permissions
Grants comprehensive project-level roles: editor, IAM admin, Compute Engine admin, network admin, Cloud SQL, Storage, BigQuery, Secret Manager, monitoring, logging, and service account management.

### Phase 5 -- Helper Scripts
Creates `scripts/apply-project-permissions.sh` for applying core permissions to new projects.

## Configuration Defaults

```bash
FOLDER_NAME="org-bootstrap"
PROJECT_ID="org-automation"
BUCKET_NAME="org-tofu-state"
BILLING_BUCKET_NAME="org-billing-usage-reports"
REGION="europe-west2"
SA_NAME="tofu-sa-org"
```

## Post-Bootstrap Setup

1. **Update `root.hcl`**:
   ```hcl
   bucket  = "org-tofu-state"
   project = "org-automation"
   ```

2. **Set up authentication**:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="$HOME/tofu-sa-org-key.json"
   export GOOGLE_PROJECT="org-automation"
   ```

3. **Test Terragrunt**:
   ```bash
   source scripts/setup_env.sh
   terragrunt init
   ```

## Security Considerations

- Store the service account key securely; consider Google Secret Manager for production
- Set up key rotation and monitor usage via Cloud Audit Logs
- The service account has broad org-level permissions -- apply least-privilege overrides for project-specific access

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Folder creation fails | Folder may already exist (script detects and continues). Check org-level permissions. |
| Billing link fails | Verify billing account ID format and permissions. |
| API enablement fails | Check service account permissions and project quotas. |

### Verification Commands

```bash
gcloud resource-manager folders list --organization=YOUR_ORG_ID
gcloud projects describe org-automation
gsutil ls gs://org-tofu-state
gsutil ls gs://org-billing-usage-reports
gcloud iam service-accounts list --project=org-automation
```

## Helper Scripts

### apply-project-permissions.sh

Applies core Terraform permissions to new projects:

```bash
./scripts/apply-project-permissions.sh NEW_PROJECT_ID
```

Roles applied: `roles/editor`, `roles/iam.securityAdmin`, `roles/compute.admin`, `roles/storage.admin`, `roles/secretmanager.admin`, `roles/serviceusage.serviceUsageAdmin`, `roles/cloudsql.admin`, `roles/bigquery.admin`.

## References

- [Google Cloud Resource Manager](https://cloud.google.com/resource-manager/docs)
- [Service Account Best Practices](https://cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)
