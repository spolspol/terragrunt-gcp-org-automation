# Secrets Setup Guide

This guide explains how to set up and deploy secrets using Google Secret Manager with Terragrunt.

## Overview

The infrastructure uses Google Secret Manager to securely store sensitive information like API keys, database credentials, and service account keys. Each secret is managed as a separate Terragrunt module.

## Prerequisites

1. **Environment Variables**: The secrets are configured to read values from environment variables at deployment time
2. **Google Cloud Authentication**: Ensure you're authenticated with appropriate permissions
3. **Terragrunt**: Have Terragrunt installed and configured

## Secret Structure

Secrets are organized in the following structure:
```
live/
└── non-production/
    └── development/
        └── dp-dev-01/
            └── secrets/
                ├── api-secret/
                │   └── terragrunt.hcl
                ├── api-key-secret/
                │   └── terragrunt.hcl
                └── db-connection-secret/
                    └── terragrunt.hcl
```

## Setup Process

### Option 1: Interactive Setup Script

Use the interactive setup script for a guided experience:

```bash
# Run the interactive setup script
./scripts/setup_secrets_env.sh
```

This script will:
- Prompt for each secret value
- Validate the format (e.g., JSON for service account keys)
- Show a summary of configured values
- Optionally save the environment variables to a file

### Option 2: Quick Setup Script

For a faster setup with minimal prompts:

```bash
# Run the quick setup script
./scripts/setup_secrets_env_simple.sh
```

### Option 3: Manual Setup

Set environment variables manually:

```bash
# API secret value
export API_SECRET_VALUE="your-secret-value"

# API key for external services
export API_KEY_SECRET="your-api-key"

# Database connection string
export DB_CONNECTION_STRING="postgresql://user:pass@host:5432/db"

# Service account key (from file)
export SERVICE_ACCOUNT_KEY=$(cat /path/to/service-account-key.json)
```

## Deployment

### Deploy Individual Secrets

```bash
# Navigate to each secret directory and deploy
cd live/non-production/development/dp-dev-01/secrets/api-secret
terragrunt apply

cd ../api-key-secret
terragrunt apply

cd ../db-connection-secret
terragrunt apply
```

### Deploy All Secrets at Once

```bash
cd live/non-production/development/dp-dev-01/secrets
terragrunt run-all apply
```

## Verification

After deployment, verify the secrets were created:

```bash
# List secrets in the project
gcloud secrets list --project=YOUR_PROJECT_ID

# Read a specific secret (requires appropriate permissions)
gcloud secrets versions access latest --secret="api-secret" --project=YOUR_PROJECT_ID
```

## Security Best Practices

1. **Never commit secrets**: Environment variables ensure secrets aren't stored in Git
2. **Use least privilege**: Grant only necessary access to secrets
3. **Rotate regularly**: Update secret values periodically
4. **Audit access**: Monitor who accesses secrets via Cloud Audit Logs
5. **Use service accounts**: Applications should use service account credentials

## Troubleshooting

### Secret not created
- Ensure the environment variable is set and not empty
- Check that you have the necessary IAM permissions
- Verify the project exists and is accessible

### Invalid format errors
- For JSON secrets (like service account keys), ensure proper JSON formatting
- Use the validation in the setup scripts to check formats

### Permission denied
- Verify you have `roles/secretmanager.admin` or appropriate permissions
- Check that the service account has necessary project access

## Secret Configuration

Each secret's `terragrunt.hcl` file follows this pattern:

```hcl
locals {
  # Read the secret value from environment variable
  secret_value = get_env("API_SECRET_VALUE", "")
}

inputs = {
  secrets = [
    {
      name           = "api-secret"
      secret_data    = local.secret_value != "" ? local.secret_value : null
      create_version = local.secret_value != "" ? true : false
    }
  ]
  # IAM bindings for secret access
  secret_accessors_list = [
    "serviceAccount:service-account@project.iam.gserviceaccount.com"
  ]
}
```

## Next Steps

1. Deploy your secrets using the methods above
2. Update your applications to read from Secret Manager
3. Remove any hardcoded secrets from your codebase
4. Set up secret rotation policies as needed
