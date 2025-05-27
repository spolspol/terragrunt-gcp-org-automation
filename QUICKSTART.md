# Quick Start Guide

## Prerequisites

1. Install OpenTofu (>= 1.6.0)
2. Install Terragrunt (>= 0.53.0)
3. Have access to a GCP project
4. Have GCP credentials configured

## Setup Steps

### 1. Update Configuration Files

Before running Terragrunt, update these values in the configuration files:

1. **Organization ID** in `live/non-production/account.hcl`:
   ```hcl
   org_id = "YOUR_ACTUAL_ORG_ID"  # Replace with your organization ID
   ```

2. **Billing Account** in `live/non-production/development/dev-01/project.hcl`:
   ```hcl
   billing_account = "YOUR_BILLING_ACCOUNT_ID"  # Format: 012345-678901-234567
   ```

3. **State Bucket Project** in `root.hcl`:
   ```hcl
   project  = "YOUR_STATE_PROJECT_ID"  # Update this to your actual GCP project for state storage
   ```

### 2. Set Environment Variables

```bash
# Source the setup script
source setup_env.sh

# This will set:
# TF_VAR_project="dev-01"
# TF_VAR_region="europe-west2"
# TF_VAR_environment_type="non-production"
```

### 3. Configure GCP Authentication

Choose one of these methods:

```bash
# Option 1: Service Account Key
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your-service-account-key.json"

# Option 2: User Credentials
gcloud auth application-default login
```

### 4. Create State Bucket

Before running Terragrunt, create the state bucket:

```bash
gsutil mb -p YOUR_STATE_PROJECT_ID -l europe-west2 gs://org-terragrunt-state
```

### 5. Initialize and Apply

```bash
cd live/non-production/development/dev-01/project
terragrunt init
terragrunt plan
terragrunt apply
```

## Troubleshooting

### Error: ParentFileNotFoundError
Make sure you're running terragrunt from within the project directory structure, not from the root.

### Error: Can't evaluate expression
Check that all configuration files exist and have the correct values set.

### Authentication Issues
Verify your GCP credentials:
```bash
gcloud auth list
gcloud config list
``` 
