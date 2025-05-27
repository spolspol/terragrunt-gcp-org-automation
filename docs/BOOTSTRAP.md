# GCP Bootstrap Process

## Overview

The `scripts/org-bootstrap.sh` script sets up the complete initial infrastructure for Terragrunt-based GCP deployments. It creates the foundational resources needed for infrastructure-as-code management.

## What the Bootstrap Creates

The bootstrap process creates:

1. **GCP Folder**: `org-bootstrap` folder under the organization
2. **GCP Project**: `org-automation` project within the bootstrap folder
3. **Service Account**: `tofu-sa-org` with organization-level permissions
4. **Service Account Key**: Saved to `$HOME/tofu-sa-org-key.json`
5. **GCS Bucket**: `org-tofu-state` for Terragrunt state storage
6. **Billing Usage Reports Bucket**: `org-billing-usage-reports` for centralized billing data
7. **Helper Script**: `scripts/apply-project-permissions.sh` for new projects

## Usage

### Basic Usage
```bash
./scripts/org-bootstrap.sh
```

### With Custom Parameters
```bash
./scripts/org-bootstrap.sh [ORG_ID] [BILLING_ACCOUNT]
```

### Parameters
- `ORG_ID`: GCP Organization ID (default: YOUR_ORG_ID)
- `BILLING_ACCOUNT`: Billing Account ID (default: YOUR_BILLING_ACCOUNT)

## Prerequisites

1. **GCP Authentication**: Must be authenticated with gcloud
   ```bash
   gcloud auth login
   ```

2. **Required APIs**: The following APIs should be enabled in your current project:
   - `cloudresourcemanager.googleapis.com`
   - `cloudbilling.googleapis.com`
   - `storage.googleapis.com`
   - `iam.googleapis.com`
   - `serviceusage.googleapis.com`

3. **Permissions**: Your account needs organization-level permissions to:
   - Create folders and projects
   - Manage IAM policies
   - Create service accounts
   - Manage billing account permissions

## Bootstrap Process Phases

### Phase 1: Service Account Creation
- Creates `tofu-sa-org` service account in current project
- Generates and saves service account key to `$HOME/tofu-sa-org-key.json`

### Phase 2: Organization Permissions
Grants the service account these organization-level roles:
- `roles/resourcemanager.folderAdmin` - Folder management
- `roles/resourcemanager.projectCreator` - Project creation
- `roles/resourcemanager.projectDeleter` - Project deletion
- `roles/resourcemanager.projectIamAdmin` - Project IAM management
- `roles/billing.user` - Billing account usage
- `roles/resourcemanager.organizationAdmin` - Organization administration
- `roles/securitycenter.adminEditor` - Security center management
- `roles/essentialcontacts.admin` - Essential contacts management

### Phase 3: GCP Infrastructure Creation
Using the service account:
1. Creates `org-bootstrap` folder under organization
2. Creates `org-automation` project in org-bootstrap folder
3. Links billing account to project
4. Enables required APIs in project
5. Creates `org-tofu-state` GCS bucket for Terragrunt state
6. Creates `org-billing-usage-reports` GCS bucket for centralized billing data
7. Enables versioning and uniform bucket-level access on both buckets

### Phase 4: Project Permissions
Grants comprehensive project-level permissions including:
- Core project management (editor, IAM admin)
- Compute Engine (admin, network admin, security admin)
- VPC and Networking (networks admin, DNS admin)
- Cloud SQL, Storage, BigQuery admin roles
- Secret Manager, monitoring, logging admin roles
- Service account management roles

### Phase 5: Helper Scripts
Creates `scripts/apply-project-permissions.sh` for applying core permissions to new projects.

## Configuration

The script uses these default values:
```bash
ORG_ID="YOUR_ORG_ID"
BILLING_ACCOUNT="YOUR_BILLING_ACCOUNT"
FOLDER_NAME="org-bootstrap"
PROJECT_ID="org-automation"
BUCKET_NAME="org-tofu-state"
BILLING_BUCKET_NAME="org-billing-usage-reports"
REGION="europe-west2"
SA_NAME="tofu-sa-org"
```

## Post-Bootstrap Setup

After successful bootstrap:

1. **Update root.hcl**:
   ```hcl
   bucket = "org-tofu-state"
   project = "org-automation"
   ```

2. **Set up authentication**:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="$HOME/tofu-sa-org-key.json"
   export GOOGLE_PROJECT="org-automation"
   ```

3. **Test Terragrunt setup**:
   ```bash
   source scripts/setup_env.sh
   terragrunt init
   ```

## Security Considerations

### Key Management
- Service account key is saved to user's home directory
- Consider storing in Google Secret Manager for production
- Set up key rotation schedule
- Monitor usage via Cloud Audit Logs

### Permissions
- Service account has broad organization-level permissions
- Apply principle of least privilege for project-specific access
- Regularly review and audit permissions

### Monitoring
- Enable Cloud Audit Logs for service account usage
- Set up alerts for suspicious activity
- Regular security reviews of IAM policies

## Troubleshooting

### Common Issues

1. **Folder Creation Fails**:
   - Folder may already exist (script will detect and continue)
   - Check organization-level permissions

2. **Billing Account Link Fails**:
   - Verify billing account ID format
   - Check billing account permissions

3. **API Enablement Fails**:
   - Ensure service account has necessary permissions
   - Check project quotas and limits

### Verification Commands

```bash
# Check folder exists
gcloud resource-manager folders list --organization=YOUR_ORG_ID

# Check project exists
gcloud projects describe org-automation

# Check buckets exist
gsutil ls gs://org-tofu-state
gsutil ls gs://org-billing-usage-reports

# Check service account
gcloud iam service-accounts list --project=org-automation
```

## Integration with Terragrunt

The bootstrap creates the foundation for the Terragrunt infrastructure:

- **State Storage**: GCS bucket for remote state
- **Authentication**: Service account for CI/CD workflows
- **Project Structure**: Bootstrap folder for infrastructure projects
- **Permissions**: Comprehensive roles for infrastructure management

The created service account can be used in:
- GitHub Actions workflows
- Local development (via key file)
- CI/CD pipelines
- Automated deployments

## Helper Scripts

### apply-project-permissions.sh
Applies core Terraform permissions to new projects:

```bash
./scripts/apply-project-permissions.sh NEW_PROJECT_ID
```

Core roles applied:
- `roles/editor`
- `roles/iam.securityAdmin`
- `roles/compute.admin`
- `roles/storage.admin`
- `roles/secretmanager.admin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/cloudsql.admin`
- `roles/bigquery.admin`
