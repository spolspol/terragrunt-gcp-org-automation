# Secret Management

This document outlines the approach to managing secrets in the Terragrunt GCP infrastructure.

## Overview

Secrets in this infrastructure are managed using Google Cloud Secret Manager. The Terragrunt configuration follows these principles:

1. **No hardcoded secrets** in code or Terraform/Terragrunt files
2. **Separation of definition and values** - infrastructure code defines which secrets exist, but not their values
3. **Principle of least privilege** - only resources that need access to a secret should have it
4. **Audit trail** - all secret access is logged and monitored

## Secret Definition vs. Population

### Definition

Secrets are defined in Terragrunt configuration files using the `secret_manager.hcl` template:

```hcl
secrets = [
  {
    name                  = "secret-name"
    automatic_replication = true
    # No secret_data defined here
  }
]
```

### Population

Secrets should be populated using one of these approved methods:

1. **Manual population** (for initial setup or emergencies):
```bash
gcloud secrets versions add secret-name --data-file=/path/to/secret/file
```

2. **CI/CD pipeline** (preferred method):
```yaml
# Example GitHub Actions workflow step
- name: Update GCP Secrets
  uses: google-github-actions/create-secret-version@v1
  with:
    secret: secret-name
    project_id: ${{ secrets.GCP_PROJECT_ID }}
    secret_value: ${{ secrets.SECRET_VALUE }}
```

3. **Automated rotation** with Cloud Functions (for service account keys and other rotatable secrets)

## Accessing Secrets

Secrets should be accessed using the appropriate GCP Secret Manager APIs:

1. **From Compute instances**:
```bash
# Example bash script
SECRET_VALUE=$(gcloud secrets versions access latest --secret="secret-name")
```

2. **From Terraform**:
```hcl
data "google_secret_manager_secret_version" "secret_name" {
  secret = "secret-name"
}

# Then reference as: data.google_secret_manager_secret_version.secret_name.secret_data
```

3. **From application code**:
```python
# Example Python code
from google.cloud import secretmanager

client = secretmanager.SecretManagerServiceClient()
name = f"projects/{project_id}/secrets/secret-name/versions/latest"
response = client.access_secret_version(request={"name": name})
secret_value = response.payload.data.decode("UTF-8")
```

## Secret Rotation

Implement regular secret rotation with these guidelines:

1. **Schedule**: Rotate all secrets at least every 90 days
2. **Overlap**: During rotation, keep old and new versions active briefly
3. **Automation**: Use automated tools for rotation when possible

For SSH keys and similar long-lived credentials, implement a rotation schedule in your CICD system.

## Encryption

Ensure all secrets are properly encrypted:

1. At-rest: Secret Manager handles this automatically
2. In-transit: Use only secure connections (HTTPS/TLS)
3. In-use: Minimize exposure, never log secret values

## Audit and Compliance

1. Enable Secret Manager audit logs:
```bash
gcloud logging sinks create secret-manager-logs \
  pubsub.googleapis.com/projects/PROJECT_ID/topics/secret-manager-logs \
  --log-filter='resource.type="audited_resource" AND resource.labels.service="secretmanager.googleapis.com"'
```

2. Regularly review access patterns and permissions
3. Implement alerting for unusual access patterns

## Emergency Procedures

In case of suspected secret compromise:

1. Immediately rotate the affected secret
2. Revoke any related tokens or credentials
3. Investigate access logs for unauthorized use
4. Document the incident and remediation steps

## Reference Implementation

The secret management infrastructure supports individual secrets in separate subfolders:

- **Template**: `_common/templates/secret_manager.hcl` - Standardized secret template
- **Common Configuration**: `secrets/secrets.hcl` - Shared settings
- **Individual Secrets**: Each secret has its own subfolder under `secrets/`:
  - `secrets/secret-name-01/terragrunt.hcl` - Individual secret configuration
  - `secrets/secret-name-02/terragrunt.hcl` - Individual secret configuration
  - `secrets/secret-name-03/terragrunt.hcl` - Individual secret configuration

For detailed information about the architecture, see [SECRETS_TEMPLATE.md](SECRETS_TEMPLATE.md).
