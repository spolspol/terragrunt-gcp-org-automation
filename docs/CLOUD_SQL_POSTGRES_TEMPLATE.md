# Cloud SQL PostgreSQL Template

Deploys Cloud SQL PostgreSQL instances using the `terraform-google-sql-db` module (v26.2.1, `modules/postgresql` submodule). The template provides environment-aware naming, private networking via Private Service Access, SSL-only connections, and password management through Secret Manager.

## Overview

| Property | Value |
|----------|-------|
| Template | `_common/templates/cloud_sql_postgres.hcl` |
| Module | `terraform-google-sql-db//modules/postgresql` |
| Version | Defined in `_common/common.hcl` as `sql_db` |
| Example instance | `live/non-production/development/functions/fn-dev-01/europe-west2/cloud-sql/postgres-main/` |

Instances are deployed with private IPs only, accessed through VPC peering (Private Service Access). Public IPs are never assigned.

## Configuration

### Key Parameters

| Parameter | Dev | Prod | Notes |
|-----------|-----|------|-------|
| `database_version` | `POSTGRES_17` | `POSTGRES_17` | Latest stable |
| `edition` | `ENTERPRISE` | `ENTERPRISE` | Use `ENTERPRISE_PLUS` only if customer-managed CA is required |
| `tier` | `db-f1-micro` | `db-custom-2-7680` | Shared CPU dev, dedicated prod |
| `disk_type` | `PD_HDD` | `PD_SSD` | Cost vs performance |
| `disk_autoresize` | `false` | `true` | Avoid surprise costs in dev |
| `availability_type` | `ZONAL` | `REGIONAL` | HA in prod only |
| `ssl_mode` | `ENCRYPTED_ONLY` | `ENCRYPTED_ONLY` | All connections require TLS |
| `deletion_protection` | `false` | `true` | Prevent accidental deletion |

### Naming Pattern

Resources are named using the project name from the hierarchy:

| Resource | Pattern | Example |
|----------|---------|---------|
| Instance | `{project}-postgres-main` | `fn-dev-01-postgres-main` |
| Database | `{project}-app` | `fn-dev-01-app` |
| User | `{project}-app` | `fn-dev-01-app` |

### Environment-Aware Configuration

Use a conditional to switch between dev and prod settings in a single file:

```hcl
locals {
  is_production = include.base.locals.environment_type == "production"

  settings = local.is_production ? {
    tier              = "db-custom-2-7680"
    disk_size         = 100
    disk_type         = "PD_SSD"
    availability_type = "REGIONAL"
  } : {
    tier              = "db-f1-micro"
    disk_size         = 10
    disk_type         = "PD_HDD"
    availability_type = "ZONAL"
  }
}
```

## Usage

Create a `terragrunt.hcl` that includes the template:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_sql_postgres_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_sql_postgres.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock-project/global/networks/mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "private_service_access" {
  config_path = "../../networking/private-service-access"
  mock_outputs = { peering_completed = true }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

locals {
  project_name  = try(dependency.project.outputs.project_name, "fn-dev-01")
  instance_name = "${local.project_name}-postgres-main"
}

inputs = {
  project_id       = dependency.project.outputs.project_id
  region           = include.base.locals.region
  name             = local.instance_name
  database_version = "POSTGRES_17"
  edition          = "ENTERPRISE"
  tier             = "db-f1-micro"
  disk_size        = 10
  disk_type        = "PD_HDD"
  availability_type = "ZONAL"

  ipv4_enabled       = false
  private_network    = dependency.network.outputs.network_self_link
  allocated_ip_range = "${local.project_name}-psa-range"
  ssl_mode           = "ENCRYPTED_ONLY"

  additional_databases = [
    { name = "${local.project_name}-app", charset = "", collation = "" }
  ]

  additional_users = [
    { name = "${local.project_name}-app", password = "", random_password = true, type = "BUILT_IN" }
  ]
}
```

## Password Management

Passwords follow a create-then-rotate workflow:

1. **Initial deploy** -- the module generates a random password (stored in Terraform state).
2. **Rotate immediately** -- generate a new password and set it on both Cloud SQL and Secret Manager:

```bash
# Generate a strong password
NEW_PASSWORD="$(python3 -c "import base64,os; print(base64.b64encode(os.urandom(32)).decode())")"

# Set on Cloud SQL
gcloud sql users set-password fn-dev-01-app \
  --instance=fn-dev-01-postgres-main \
  --project=<PROJECT_ID> \
  --password="$NEW_PASSWORD"

# Store in Secret Manager
echo -n "$NEW_PASSWORD" | gcloud secrets versions add gke-pipeline-cloudsql-password \
  --data-file=- --project=<PROJECT_ID>
```

For GKE workloads, use External Secrets Operator to sync the secret into Kubernetes:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudsql-password
spec:
  secretStoreRef:
    name: gcpsm-secret-store
    kind: SecretStore
  target:
    name: cloudsql-credentials
  data:
  - secretKey: password
    remoteRef:
      key: gke-pipeline-cloudsql-password
```

## Dependencies

1. **Project** -- target GCP project with `sqladmin.googleapis.com` enabled
2. **VPC network** -- the network where the instance will receive a private IP
3. **Private Service Access** -- peering must be complete before the instance can be created
4. **Secret Manager** (optional) -- for storing the rotated password

## SSL

All instances enforce `ssl_mode = "ENCRYPTED_ONLY"`, requiring TLS for every connection. The standard connection string is:

```
postgresql://USER:PASSWORD@PRIVATE_IP:5432/DATABASE?sslmode=require  # pragma: allowlist secret
```

For environments that require mutual TLS, set `ssl_mode = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"` and generate client certificates. See the [Cloud SQL SSL documentation](https://cloud.google.com/sql/docs/postgres/configure-ssl-instance) for details.

For customer-managed CA integration (requires `ENTERPRISE_PLUS` edition), see [CAS_PKI.md](CAS_PKI.md).

## Troubleshooting

1. **"database already exists"** -- import it into state:
   ```bash
   terragrunt import 'google_sql_database.default[0]' \
     'projects/PROJECT_ID/instances/INSTANCE_NAME/databases/DATABASE_NAME'  # pragma: allowlist secret
   ```

2. **State lock error** -- force-unlock with `terragrunt force-unlock LOCK_ID`.

3. **Permission denied** -- the service account needs `roles/cloudsql.admin` for full management or `roles/cloudsql.editor` for create/update.

4. **Private IP not assigned** -- verify Private Service Access peering is complete and `allocated_ip_range` matches the PSA range name.

5. **Connection refused from GKE** -- ensure VPC firewall allows TCP 5432 from the GKE pod CIDR to the Cloud SQL private IP range.

## References

- [Cloud SQL for PostgreSQL](https://cloud.google.com/sql/docs/postgres)
- [terraform-google-sql-db module](https://github.com/terraform-google-modules/terraform-google-sql-db)
- [Private Service Access](https://cloud.google.com/vpc/docs/private-services-access)
- [Cloud SQL SSL configuration](https://cloud.google.com/sql/docs/postgres/configure-ssl-instance)
- [External Secrets Operator](https://external-secrets.io/)
- [CAS PKI Implementation](CAS_PKI.md)
