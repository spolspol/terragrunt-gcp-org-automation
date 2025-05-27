# GCP Authentication Guide

## Overview

This guide provides comprehensive instructions for setting up Google Cloud Platform (GCP) authentication for use with infrastructure as code tools like OpenTofu and Terragrunt. Proper authentication is critical for securely managing cloud resources.

## Authentication Methods

GCP offers several authentication methods:

1. **User Account** - Your personal Google account credentials
2. **Service Account** - A dedicated account for applications or automation
3. **Workload Identity Federation** - Federated authentication for non-GCP workloads
4. **Application Default Credentials (ADC)** - A strategy to find credentials automatically

For infrastructure automation, **Service Accounts** are recommended.

## Service Account Setup

### Creating a Terraform Service Account

1. **Navigate to IAM & Admin > Service Accounts** in the GCP Console
2. Click **Create Service Account**
3. Enter the following details:
   ```
   Name: terraform-admin
   Description: Service account for infrastructure management
   ```
4. Click **Create and Continue**
5. **Assign appropriate roles** based on what resources you'll be managing:
   - For development environments (not recommended for production):
     - `roles/editor`
   - For production (preferred, more secure approach):
     - `roles/compute.admin`
     - `roles/storage.admin`
     - `roles/iam.serviceAccountUser`
     - `roles/resourcemanager.projectIamAdmin`
     - `roles/secretmanager.admin`
     - `roles/bigquery.admin`
     - `roles/cloudsql.admin`
6. Click **Continue** and then **Done**

### Creating a Service Account Key

1. In the Service Accounts list, find your new service account
2. Click the three dots menu on the right and select **Manage keys**
3. Click **Add Key > Create new key**
4. Select **JSON** as the key type
5. Click **Create** to download the key file
6. Store this key file securely - it grants access to your GCP resources

## Local Authentication Setup

### Method 1: Environment Variable (Recommended)

1. Store the key file in a secure location not tracked by Git
2. Set the environment variable to point to your key file:

   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your-project-credentials.json"
   ```

3. For convenience, add to your shell profile:

   ```bash
   echo 'export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your-project-credentials.json"' >> ~/.bashrc
   source ~/.bashrc
   ```

### Method 2: gcloud Authentication

1. Install the Google Cloud SDK if not already installed
2. Authenticate with gcloud:

   ```bash
   gcloud auth login
   ```

3. Set your default project:

   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```

4. Set application default credentials:

   ```bash
   gcloud auth application-default login
   ```

## Verification

Verify your authentication is working correctly:

```bash
# Using gcloud
gcloud auth list
gcloud projects describe YOUR_PROJECT_ID

# Using service account with GOOGLE_APPLICATION_CREDENTIALS
gcloud auth application-default print-access-token
```

## Provider Configuration

The root.hcl file in this repository is already configured to use your authentication:

```hcl
provider "google" {
  project = var.project
  region  = var.region
}
```

This will automatically use the credentials from the GOOGLE_APPLICATION_CREDENTIALS environment variable or gcloud application default credentials.

## Security Best Practices

1. **Never commit service account keys** to version control
   - Add `*.json` to your `.gitignore` file
   - Consider using Git hooks to prevent accidental commits

2. **Rotate keys regularly**
   - Every 90 days is recommended
   - Create a new key before deleting the old one

3. **Use minimal permissions**
   - Follow the principle of least privilege
   - Create different service accounts for different purposes

4. **Use different service accounts for different environments**
   - Development
   - Staging
   - Production

5. **Consider using Workload Identity Federation**
   - For CI/CD pipelines
   - Avoids the need for service account keys

6. **Audit service account usage**
   - Enable audit logging
   - Review service account activity regularly

## Handling Multiple Projects

When working with multiple GCP projects:

1. **Create separate service accounts** for each project
2. Create a shell script to easily switch between credentials:

   ```bash
   # ~/bin/switch-gcp-project.sh
   #!/bin/bash
   if [ "$1" == "project1" ]; then
     export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.gcp/project1-credentials.json"
   elif [ "$1" == "project2" ]; then
     export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.gcp/project2-credentials.json"
   else
     echo "Unknown project: $1"
     echo "Usage: switch-gcp-project [project1|project2]"
     return 1
   fi
   echo "Switched to GCP project: $1"
   ```

3. Make it executable and use it:

   ```bash
   chmod +x ~/bin/switch-gcp-project.sh
   source ~/bin/switch-gcp-project.sh project1
   ```

## Troubleshooting

### Common Issues

1. **"Could not load the default credentials"**
   - Ensure GOOGLE_APPLICATION_CREDENTIALS is set correctly
   - Verify the path to your key file is correct
   - Check file permissions (should be readable by your user)

2. **Permission denied errors**
   - Verify your service account has the necessary roles
   - Check if you're operating in the correct project

3. **Expired credentials**
   - For user credentials: `gcloud auth login` again
   - For service accounts: verify the key hasn't been revoked

4. **"Provider produced inconsistent final plan"**
   - Clear the OpenTofu/Terragrunt cache:
     ```bash
     rm -rf .terraform .terragrunt-cache
     terragrunt init
     ```

### Getting Help

Run the following to gather information for troubleshooting:

```bash
gcloud info
gcloud config list
echo $GOOGLE_APPLICATION_CREDENTIALS
ls -la $GOOGLE_APPLICATION_CREDENTIALS
```

## References

- [GCP Service Accounts Documentation](https://cloud.google.com/iam/docs/service-accounts)
- [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Google Provider Authentication](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference#authentication)
