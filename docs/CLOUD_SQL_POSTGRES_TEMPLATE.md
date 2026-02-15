<!-- Space: PE -->
<!-- Title: Cloud SQL PostgreSQL Template -->
<!-- Parent: Compute Resources -->
<!-- Label: template -->
<!-- Label: cloud-sql -->
<!-- Label: postgresql -->
<!-- Label: database -->
<!-- Label: howto -->
<!-- Label: intermediate -->

# Cloud SQL PostgreSQL Template Documentation

## Overview

This template provides a standardized configuration for deploying Cloud SQL PostgreSQL instances across different environments using Terragrunt and OpenTofu. It implements dynamic environment-based naming patterns, secure password management via Google Secret Manager, and cost-optimized configurations suitable for development and production workloads.

### Key Features
- **PostgreSQL 17** - Latest version with full feature set
- **Dynamic environment-based naming** - Automatically adapts to environment context
- **Secure password management** - Integration with Google Secret Manager
- **Private Service Access** - Secure private IP connectivity
- **SSL-only connections** - ENCRYPTED_ONLY mode enforces TLS/SSL for all connections
- **Client certificate support** - Generate and manage client certificates for enhanced security
- **Cost optimization** - Configurable tiers for different environments
- **Data pipeline integration** - Pre-configured for workflow orchestration

## Template Configuration

### Template Location
```
_common/templates/cloud_sql_postgres.hcl
```

### Module Source
```hcl
terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-sql-db.git//modules/postgresql?ref=${local.module_versions.sql_db}"
}
```

### Required Dependencies

The template requires the following dependencies to be configured:

1. **VPC Network** - For private network connectivity
2. **Private Service Access** - For private IP allocation
3. **Project** - Target GCP project
4. **Secret Manager** - For password storage (optional but recommended)

Example dependency configuration:
```hcl
dependency "vpc-network" {
  config_path = "../../../vpc-network"
}

dependency "private_service_access" {
  config_path = "../../networking/private-service-access"
}

dependency "project" {
  config_path = "../../../project"
}

dependency "pipeline_password_secret" {
  config_path = "../../../secrets/gke-pipeline-cloudsql-password"
}
```

## Dynamic Naming Pattern

The template uses environment variables to create consistent, environment-specific resource names:

### Environment Variables
```hcl
# With the base.hcl include pattern, environment variables are accessed via:
include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

# Access environment name
# include.base.locals.merged.environment_name  # e.g., "dp-dev-01"
```

### Naming Patterns

| Resource | Pattern | Example |
|----------|---------|---------|
| **Instance Name** | `${environment_name}-postgres-main` | `dp-dev-01-postgres-main` |
| **Database Name** | `${environment_name}-pipeline-db` | `dp-dev-01-pipeline-db` |
| **User Name** | `${environment_name}-pipeline-db` | `dp-dev-01-pipeline-db` |
| **Labels** | Uses environment variables | `project: dp-dev-01` |

### Implementation Example
```hcl
inputs = {
  name = "${include.base.locals.merged.environment_name}-postgres-main"

  additional_databases = [
    {
      name      = "${include.base.locals.merged.environment_name}-pipeline-db"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    }
  ]

  additional_users = [
    {
      name            = "${include.base.locals.merged.environment_name}-pipeline-db"
      password        = ""
      random_password = true
    }
  ]
}
```

## Password Management

### Auto-Generation
Passwords are automatically generated using Terraform's random_password resource:
```hcl
additional_users = [
  {
    name            = "${include.base.locals.merged.environment_name}-pipeline-db"
    password        = ""        # Leave empty for auto-generation
    random_password = true      # Enable random password generation
  }
]
```

### Secret Manager Integration

#### Workflow
1. **Deploy Secret placeholder**:
   ```bash
   cd live/non-production/development/dp-dev-01/secrets/gke-pipeline-cloudsql-password
   # Optional (local/manual): create the first secret version via Terragrunt using TF_VAR_* (stored in state):
   # export TF_VAR_pipeline_cloudsql_password="..."  # pragma: allowlist secret
   GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json terragrunt apply --auto-approve
   ```

   Optional (GitHub Actions): set the value via GitHub Environment/Repository secrets and expose it as `TF_VAR_pipeline_cloudsql_password` in the workflow environment (stored in state).

2. **Deploy Cloud SQL instance**:
   ```bash
   cd ../../europe-west2/cloud-sql/postgres-main
   GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json terragrunt apply --auto-approve
   ```

3. **Manually set a new password** (do not store the module-generated password):
   ```bash
   NEW_PASSWORD="$(python3 - <<'PY'
import base64, os
print(base64.b64encode(os.urandom(32)).decode())
PY
)"  # pragma: allowlist secret
   ```

4. **Set the Cloud SQL user password**:
   ```bash
   gcloud sql users set-password dp-dev-01-pipeline-db \
     --instance=dp-dev-01-postgres-main \
     --project=dp-dev-01-a \
     --password="$NEW_PASSWORD"  # pragma: allowlist secret
   ```

5. **Update Secret Manager** (add a new version):
   ```bash
   echo -n "$NEW_PASSWORD" | gcloud secrets versions add gke-pipeline-cloudsql-password \
     --data-file=- --project=dp-dev-01-a  # pragma: allowlist secret
   ```

### Kubernetes Integration

For GKE workloads, use one of these methods:

#### External Secrets Operator
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: pipeline-cloudsql-password
spec:
  secretStoreRef:
    name: gcpsm-secret-store
    kind: SecretStore
  target:
    name: pipeline-cloudsql-credentials
  data:
  - secretKey: password
    remoteRef:
      key: gke-pipeline-cloudsql-password
```

#### Workload Identity
```bash
kubectl annotate serviceaccount pipeline-sa \
  iam.gke.io/gcp-service-account=pipeline-sa@project.iam.gserviceaccount.com
```

## Cost Optimization

### Development Configuration
```hcl
# Minimal resources for cost optimization
tier              = "db-f1-micro"  # Shared CPU, 0.6GB RAM (~$8/month)
disk_size         = 10              # Minimum disk size in GB
disk_type         = "PD_HDD"        # Cheaper than SSD
disk_autoresize   = false
availability_type = "ZONAL"         # Not regional (cheaper)

# Minimal backup configuration
backup_configuration = {
  enabled                        = true
  start_time                     = "02:00"
  point_in_time_recovery_enabled = false  # Disabled to save cost
  transaction_log_retention_days = 1      # Minimum retention
  retained_backups               = 7      # 7 days of backups
}
```

### Production Configuration
```hcl
# Production-ready configuration
tier              = "db-custom-2-7680"  # 2 vCPUs, 7.5GB RAM
disk_size         = 100                 # Adequate storage
disk_type         = "PD_SSD"            # Better performance
disk_autoresize   = true                # Auto-scale storage
availability_type = "REGIONAL"          # High availability

# Production backup configuration
backup_configuration = {
  enabled                        = true
  start_time                     = "02:00"
  point_in_time_recovery_enabled = true   # Enable PITR
  transaction_log_retention_days = 7      # 7 days of transaction logs
  retained_backups               = 30     # 30 days of backups
}
```

### Cost Comparison

| Tier | vCPUs | RAM | Monthly Cost (Estimated) | Use Case |
|------|-------|-----|--------------------------|----------|
| db-f1-micro | Shared | 0.6GB | ~$8 | Development/Testing |
| db-g1-small | Shared | 1.7GB | ~$25 | Light Production |
| db-custom-1-3840 | 1 | 3.75GB | ~$50 | Small Production |
| db-custom-2-7680 | 2 | 7.5GB | ~$100 | Standard Production |
| db-custom-4-16384 | 4 | 16GB | ~$200 | High-Performance |

## Data Pipeline Integration Requirements

### Overview

Data pipeline tools require multiple integration points to function properly:
1. **Cloud SQL** - For workflow metadata and state management
2. **BigQuery** - For data processing and analytics workloads
3. **Cloud Storage** - For data lake and artifact storage
4. **Service Account Key** - For GCP resource authentication

### Required Secrets

For a complete data pipeline deployment, ensure these secrets are configured:

| Secret | Purpose | Location |
|--------|---------|----------|
| `gke-pipeline-cloudsql-password` | Database authentication | `live/.../secrets/gke-pipeline-cloudsql-password/` |
| `gke-pipeline-dbt-client-certs` | SSL client certificates for Cloud SQL | `live/.../secrets/gke-pipeline-dbt-client-certs/` |
| `gke-pipeline-sa-key` | Service account key for BigQuery/GCS access | `live/.../secrets/gke-pipeline-sa-key/` |

### Service Account Configuration

The pipeline service account (`pipeline-sa@dp-dev-01-a.iam.gserviceaccount.com`) needs:

```bash
# BigQuery permissions for data pipeline processing
roles/bigquery.dataEditor
roles/bigquery.jobUser

# Cloud Storage for data lake operations
roles/storage.objectAdmin

# Optional: Cloud SQL client for IAM authentication
roles/cloudsql.client
```

### Deployment Checklist

1. **Deploy Cloud SQL Instance** with SSL-only connections
2. **Create Database and User** (`dp-dev-01-pipeline-db`)
3. **Generate Client Certificates** for secure connections
4. **Create Service Account** with BigQuery and GCS permissions
5. **Store Service Account Key** in Secret Manager
6. **Configure External Secrets** for Kubernetes integration
7. **Mount Secrets in Pods** for application access

### Connection Configuration

Data pipeline pods need both database connectivity and GCP access:

```yaml
env:
  # Database connection
  - name: PIPELINE_POSTGRES_HOST
    value: "postgres-main.dp-dev-01.dev.example.io"
  - name: PIPELINE_POSTGRES_DB
    value: "dp-dev-01-pipeline-db"
  - name: PIPELINE_POSTGRES_USER
    value: "dp-dev-01-pipeline-db"
  - name: PIPELINE_POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: pipeline-cloudsql-password
        key: password

  # GCP authentication for BigQuery/GCS
  - name: GOOGLE_APPLICATION_CREDENTIALS
    value: /var/secrets/gcp/key.json

volumeMounts:
  # SSL certificates for Cloud SQL
  - name: postgresql-certs
    mountPath: /etc/postgresql-certs
    readOnly: true
  # Service account key for GCP access
  - name: gcp-sa-key
    mountPath: /var/secrets/gcp
    readOnly: true
```

## Integration Points

### Private Service Access
```hcl
ip_configuration = {
  ipv4_enabled        = false  # No public IP
  private_network     = dependency.vpc-network.outputs.network_self_link
  allocated_ip_range  = dependency.private_service_access.outputs.google_compute_global_address_name

  # SSL Configuration Options:
  # Option 1: Force SSL/TLS for all connections (recommended)
  ssl_mode = "ENCRYPTED_ONLY"

  # Option 2: Maximum security with client certificates (high-security)
  # ssl_mode = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"

  authorized_networks = []
}
```

### VPC Network Connectivity
- Instances are deployed with private IPs only
- Access via Private Service Access peering
- No public IP reduces attack surface

### GKE Workload Access

#### Connection String Format

##### Standard SSL Connection (Required with ENCRYPTED_ONLY mode):
```
postgresql://[USER]:[PASSWORD]@[PRIVATE_IP]:5432/[DATABASE]?sslmode=require
```

##### With Client Certificates (Enhanced Security):
```
postgresql://[USER]:[PASSWORD]@[PRIVATE_IP]:5432/[DATABASE]?sslmode=verify-full&sslcert=/etc/postgresql-certs/client.crt&sslkey=/etc/postgresql-certs/client.key&sslrootcert=/etc/postgresql-certs/ca.crt
```

#### Example for Data Pipeline
```
# Standard SSL connection
postgresql://dp-dev-01-pipeline-db:[PASSWORD]@postgres-main.dp-dev-01.dev.example.io:5432/dp-dev-01-pipeline-db?sslmode=require

# With client certificates
postgresql://dp-dev-01-pipeline-db:[PASSWORD]@postgres-main.dp-dev-01.dev.example.io:5432/dp-dev-01-pipeline-db?sslmode=verify-full&sslcert=/etc/postgresql-certs/client.crt&sslkey=/etc/postgresql-certs/client.key&sslrootcert=/etc/postgresql-certs/ca.crt
```

### Firewall Rules
Ensure appropriate firewall rules exist:
```hcl
# Allow GKE to Cloud SQL
resource "google_compute_firewall" "allow-gke-to-cloudsql" {
  name    = "allow-gke-to-cloudsql"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["10.0.0.0/8"]  # GKE pod CIDR
  target_tags   = ["cloudsql"]
}
```

## Deployment Workflow

### Step-by-Step Deployment

1. **Navigate to the Cloud SQL directory**:
   ```bash
   cd live/non-production/development/dp-dev-01/europe-west2/cloud-sql/postgres-main
   ```

2. **Set authentication**:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json
   ```

3. **Initialize Terragrunt**:
   ```bash
   terragrunt run init
   ```

4. **Review the plan**:
   ```bash
   terragrunt run plan
   ```

5. **Apply configuration**:
   ```bash
   terragrunt apply --auto-approve
   ```

6. **Import existing resources if needed**:
   ```bash
   # If postgres database already exists
   terragrunt import 'google_sql_database.default[0]' \
     'projects/dp-dev-01-a/instances/dp-dev-01-postgres-main/databases/postgres'
   ```

7. **Retrieve outputs**:
   ```bash
   terragrunt output instance_name
   terragrunt output instance_first_ip_address
   ```

### Common Issues and Solutions

#### Issue: Database already exists
**Solution**: Import the existing database into Terraform state
```bash
terragrunt import 'google_sql_database.default[0]' \
  'projects/PROJECT_ID/instances/INSTANCE_NAME/databases/DATABASE_NAME' # pragma: allowlist secret
```

#### Issue: State lock error
**Solution**: Force unlock the state
```bash
terragrunt force-unlock LOCK_ID
```

#### Issue: Permission denied
**Solution**: Ensure service account has required permissions
- `cloudsql.admin` role for full management
- `cloudsql.editor` role for create/update operations

## Example Configurations

### Development Environment
```hcl
# terragrunt.hcl for development
inputs = {
  name       = "${include.base.locals.merged.environment_name}-postgres-main"
  project_id = dependency.project.outputs.project_id
  region     = local.region

  database_version = "POSTGRES_17"
  tier            = "db-f1-micro"
  disk_size       = 10
  disk_type       = "PD_HDD"

  deletion_protection = false

  additional_databases = [
    {
      name      = "${include.base.locals.merged.environment_name}-pipeline-db"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    }
  ]

  additional_users = [
    {
      name            = "${include.base.locals.merged.environment_name}-pipeline-db"
      password        = ""
      random_password = true
    }
  ]

  user_labels = {
    environment = include.base.locals.environment
    project     = include.base.locals.merged.environment_name
    primary_app = "${include.base.locals.merged.environment_name}-pipeline-db"
    purpose     = "workflow-metadata"
  }
}
```

### Production Environment
```hcl
# terragrunt.hcl for production
inputs = {
  name       = "${include.base.locals.merged.environment_name}-postgres-main"
  project_id = dependency.project.outputs.project_id
  region     = local.region

  database_version  = "POSTGRES_17"
  tier             = "db-custom-4-16384"
  disk_size        = 500
  disk_type        = "PD_SSD"
  disk_autoresize  = true
  availability_type = "REGIONAL"

  deletion_protection = true

  backup_configuration = {
    enabled                        = true
    start_time                     = "02:00"
    point_in_time_recovery_enabled = true
    transaction_log_retention_days = 7
    retained_backups               = 30
  }

  maintenance_window_day          = 7  # Sunday
  maintenance_window_hour         = 3  # 3 AM UTC
  maintenance_window_update_track = "stable"

  additional_databases = [
    {
      name      = "${include.base.locals.merged.environment_name}-pipeline-db"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    },
    {
      name      = "${include.base.locals.merged.environment_name}-analytics"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    }
  ]

  additional_users = [
    {
      name            = "${include.base.locals.merged.environment_name}-pipeline-db"
      password        = ""
      random_password = true
    },
    {
      name            = "${include.base.locals.merged.environment_name}-analytics"
      password        = ""
      random_password = true
    }
  ]
}
```

### Multi-Environment Setup
```hcl
# Use conditionals for environment-specific settings
locals {
  is_production = include.base.locals.environment_type == "production"

  instance_settings = local.is_production ? {
    tier              = "db-custom-4-16384"
    disk_size         = 500
    disk_type         = "PD_SSD"
    availability_type = "REGIONAL"
  } : {
    tier              = "db-f1-micro"
    disk_size         = 10
    disk_type         = "PD_HDD"
    availability_type = "ZONAL"
  }
}

inputs = {
  name             = "${include.base.locals.merged.environment_name}-postgres-main"
  database_version = "POSTGRES_17"
  tier             = local.instance_settings.tier
  disk_size        = local.instance_settings.disk_size
  disk_type        = local.instance_settings.disk_type
  availability_type = local.instance_settings.availability_type
  # ... other configurations
}
```

## Best Practices

1. **Always use environment variables** for naming to ensure consistency across environments
2. **Never hardcode passwords** - use Secret Manager and manual reset workflow
3. **Start with minimal resources** in development and scale up as needed
4. **Enable deletion protection** in production environments
5. **Use Private Service Access** for secure connectivity
6. **Implement proper backup strategies** based on RPO/RTO requirements
7. **Monitor costs** regularly and adjust instance sizes as needed
8. **Use labels consistently** for resource organization and cost tracking
9. **Document any environment-specific customizations** in the terragrunt.hcl file
10. **Test disaster recovery procedures** regularly in non-production environments

## Module Outputs

The Cloud SQL module provides these key outputs:

| Output | Description | Example |
|--------|-------------|---------|
| `instance_name` | The name of the database instance | `dp-dev-01-postgres-main` |
| `instance_connection_name` | The connection name for the database instance | `project:region:instance` |
| `instance_first_ip_address` | The first IPv4 address of the instance | `10.199.16.5` |
| `generated_user_password` | Map of generated passwords by user (do not store; reset manually) | `{"dp-dev-01-pipeline-db": "..."}` |
| `additional_users` | List of additional users created | `[{name: "dp-dev-01-pipeline-db"}]` |
| `additional_databases` | List of additional databases created | `[{name: "dp-dev-01-pipeline-db"}]` |

## SSL Configuration and Client Certificates

### SSL-Only Connections

As of 2025-09-17, all Cloud SQL PostgreSQL instances enforce SSL-only connections using `ssl_mode = "ENCRYPTED_ONLY"`. This ensures:
- **All connections are encrypted** - No plaintext data transmission
- **Protection against eavesdropping** - Data in transit is secure
- **Compliance with security standards** - Meets enterprise security requirements

### Client Certificate Management

#### Certificate Generation Script

A utility script is provided to generate and manage client certificates:

**Location**: `live/non-production/development/dp-dev-01/europe-west2/cloud-sql/postgres-main/generate-client-cert.sh`

**Usage**:
```bash
# Generate certificate and store in Secret Manager
./generate-client-cert.sh <client-name> --save-to-secret --secret-name <secret-name>

# Example for pipeline DBT
./generate-client-cert.sh pipeline-dbt-gke --save-to-secret --secret-name gke-pipeline-dbt-client-certs
```

**Options**:
- `--save-to-secret` - Store certificates in Google Secret Manager
- `--secret-name NAME` - Custom secret name (default: postgresql-client-certs)
- `--output-format FORMAT` - Output format: json|base64|files (default: json)
- `--output-dir DIR` - Directory for file output (default: ./certs)
- `--cleanup` - Remove local files after generation

#### Secret Storage

Client certificates are stored in Google Secret Manager as JSON with PEM-formatted certificates:

```json
{
  "ca.crt": "-----BEGIN CERTIFICATE-----\n...",
  "client.crt": "-----BEGIN CERTIFICATE-----\n...",
  "client.key": "-----BEGIN RSA PRIVATE KEY-----\n..."
}
```

**Secret Configuration**: `live/non-production/development/dp-dev-01/secrets/gke-pipeline-dbt-client-certs/`

#### Kubernetes Integration

For GKE workloads, certificates can be accessed via:

1. **External Secrets Operator** - Automatically sync to Kubernetes secrets
2. **Workload Identity** - Direct access to Secret Manager

**Example Kubernetes Secret**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-client-certs
  namespace: <namespace>
type: Opaque
stringData:
  ca.crt: <PEM-formatted-ca-cert>
  client.crt: <PEM-formatted-client-cert>
  client.key: <PEM-formatted-client-key>
```

**Volume Mount Configuration**:
```yaml
volumeMounts:
- name: postgresql-certs
  mountPath: /etc/postgresql-certs
  readOnly: true

volumes:
- name: postgresql-certs
  secret:
    secretName: postgresql-client-certs
    defaultMode: 0400
```

### SSL Mode Options

| Mode | Description | Use Case |
|------|-------------|----------|
| `ENCRYPTED_ONLY` | Requires SSL/TLS for all connections | Standard security (DEFAULT) |
| `TRUSTED_CLIENT_CERTIFICATE_REQUIRED` | Requires valid client certificates | High-security environments |
| `ALLOW_UNENCRYPTED_AND_ENCRYPTED` | Allows both SSL and non-SSL | Not recommended |

### Verifying SSL Configuration

Check current SSL configuration:
```bash
gcloud sql instances describe <instance-name> --project=<project-id> \
  --format="value(settings.ipConfiguration.sslMode)"
```

List client certificates:
```bash
gcloud sql ssl client-certs list \
  --instance=<instance-name> \
  --project=<project-id>
```

## Customer-Managed CA Configuration

### Overview

Cloud SQL supports three server CA modes for issuing server certificates:

| CA Mode | Description | Use Case |
|---------|-------------|----------|
| `GOOGLE_MANAGED_INTERNAL_CA` | Per-instance CA (default) | Standard deployments |
| `GOOGLE_MANAGED_CAS_CA` | Shared regional CA managed by Google | Simplified management |
| `CUSTOMER_MANAGED_CAS_CA` | Customer controls CA hierarchy via CAS | Enterprise PKI integration |

### When to Use Customer-Managed CA

Use `CUSTOMER_MANAGED_CAS_CA` when:
- You need centralised certificate management across environments
- You want to integrate with existing PKI infrastructure
- You require custom certificate policies or issuance constraints
- Compliance requires customer-controlled certificate chains

### Configuration

```hcl
ip_configuration = {
  ipv4_enabled       = false
  private_network    = dependency.vpc-network.outputs.network_self_link
  allocated_ip_range = dependency.private_service_access.outputs.google_compute_global_address_name

  # mTLS: Require valid client certificates
  ssl_mode = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"

  # Customer-managed CA from CAS
  server_ca_mode = "CUSTOMER_MANAGED_CAS_CA"
  server_ca_pool = "projects/<PKI_PROJECT>/locations/<REGION>/caPools/<CA_POOL>"

  authorized_networks = []
}
```

### IAM Requirements

The Cloud SQL service agent needs permission to request certificates from the CA pool. Add this binding in the PKI project's IAM configuration:

```hcl
# In the PKI project's iam-bindings/terragrunt.hcl
service_account_roles = {
  "serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-cloud-sql.iam.gserviceaccount.com" = [
    "roles/privateca.certificateRequester",
  ]
}
```

**Important:** The binding must be on the PKI project where the CA pool resides, not the project where Cloud SQL is deployed.

### Edition Requirements

**Important:** Customer-managed CA requires `ENTERPRISE_PLUS` edition, which is incompatible with smaller tier instances like `db-f1-micro`. If you need customer-managed CA:

| Edition | Compatible Tiers | Approximate Cost |
|---------|-----------------|------------------|
| ENTERPRISE | db-f1-micro, db-g1-small, db-n1-* | ~$15/month+ |
| ENTERPRISE_PLUS | db-perf-optimized-N-* only | ~$200/month+ |

For cost-sensitive environments like UAT, use Google-managed CA with `ENCRYPTED_ONLY` SSL mode instead.

### UAT Example (Google-Managed CA)

The dp-dev-01 Cloud SQL instance uses Google-managed CA for cost optimisation:

| Component | Value |
|-----------|-------|
| Instance | `dp-dev-01-postgres-main` |
| Edition | `ENTERPRISE` |
| SSL Mode | `ENCRYPTED_ONLY` |
| CA Type | Google-managed |
| DNS | `postgres-main.dp-dev-01.uat.example.io` |

**Location:** `live/non-production/uat/data-platform/dp-dev-01/europe-west2/cloud-sql/postgres-main/`

> **Note:** Originally planned to use customer-managed CA from UAT CAS (`org-uat-pool-01`), but switched to Google-managed CA due to `ENTERPRISE_PLUS` edition requirement (~$200+/month vs ~$15/month).

### Certificate Chain (Customer-Managed)

When using customer-managed CA with `ENTERPRISE_PLUS` edition, the certificate chain is:

```
Root CA (org-pki-hub)
└── Subordinate CA (uat-pki)
    └── Cloud SQL Server Certificate
```

Clients connecting with `sslmode=verify-full` will validate the entire chain.

### Verification Commands

```bash
# Verify Cloud SQL instance CA configuration
gcloud sql instances describe <instance-name> --project=<project-id> \
  --format="yaml(settings.ipConfiguration.serverCaMode,settings.ipConfiguration.serverCaPool,settings.ipConfiguration.sslMode)"

# Verify IAM on CA pool
gcloud privateca pools get-iam-policy <ca-pool> \
  --project=<pki-project> \
  --location=<region>

# View server certificate details
gcloud sql instances describe <instance-name> --project=<project-id> \
  --format="yaml(serverCaCert)"
```

### References

- [Customer-managed CA for Cloud SQL](https://docs.cloud.google.com/sql/docs/postgres/customer-managed-ca)
- [CAS PKI Implementation](CAS_PKI.md)

## References

- [Google Cloud SQL for PostgreSQL Documentation](https://cloud.google.com/sql/docs/postgres)
- [Terraform Google SQL DB Module](https://github.com/terraform-google-modules/terraform-google-sql-db)
- [Private Service Access Documentation](https://cloud.google.com/vpc/docs/private-services-access)
- [Google Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [External Secrets Operator](https://external-secrets.io/latest/)
- [Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Customer-managed CA for Cloud SQL](https://docs.cloud.google.com/sql/docs/postgres/customer-managed-ca)
