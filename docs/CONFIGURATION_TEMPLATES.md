# Configuration Templates

Reusable Terragrunt templates in `_common/templates/` standardise GCP resource deployment across environments. Each template wraps a Terraform module with environment-aware defaults, consistent naming, and centrally managed versions from `_common/common.hcl`.

## Available Templates

| Category | Template | File | Description |
|----------|----------|------|-------------|
| **Infrastructure** | Folder | `folder.hcl` | GCP folder creation and IAM (v5.0.0) |
| | Project | `project.hcl` | Project creation via Project Factory (v18.0.0) |
| | Network | `network.hcl` | VPC networks, subnets, firewall rules (v12.0.0) |
| | Private Service Access | `private_service_access.hcl` | VPC peering for managed services (v1.0.4) |
| **Compute** | Compute Instance | `compute_instance.hcl` | VM instances |
| | Instance Template | `instance_template.hcl` | Reusable VM templates |
| | GKE | `gke.hcl` | Google Kubernetes Engine clusters |
| **Networking** | Cloud Router | `cloud-router.hcl` | Regional Cloud Routers |
| | Cloud NAT | `cloud-nat.hcl` | NAT gateways for private subnets |
| | External IP | `external_ip.hcl` | Static external IP addresses |
| | Internal IP | `internal_ip.hcl` | Static internal IP addresses |
| | VPC Peering | `vpc_peering.hcl` | VPC network peering |
| | NCC | `ncc.hcl` | Network Connectivity Center |
| **Serverless** | Cloud Run | `cloud-run.hcl` | Serverless container services |
| | Load Balancer | (inline config) | External Application Load Balancer |
| **Storage** | Cloud Storage | `cloud_storage.hcl` | GCS buckets with lifecycle rules (v11.0.0) |
| | BigQuery | `bigquery.hcl` | Datasets, tables, and views (v10.1.0) |
| | Artifact Registry | `artifact_registry.hcl` | Container and package registries |
| **Database** | Cloud SQL | `cloud_sql.hcl` | SQL Server instances |
| | Cloud SQL PostgreSQL | `cloud_sql_postgres.hcl` | PostgreSQL instances |
| **DNS** | Cloud DNS | `cloud_dns.hcl` | DNS zones and records |
| | Cloud DNS Peering | `cloud_dns_peering.hcl` | DNS peering across VPCs |
| **Security** | Secret Manager | `secret_manager.hcl` | Secret management and access control |
| | IAM Bindings | `iam_bindings.hcl` | Project-level IAM bindings |
| | Firewall Rules | `firewall_rules.hcl` | VPC firewall rules |
| | Cloud Armor | `cloud_armor.hcl` | WAF and DDoS protection policies |
| **IAM** | Org IAM Bindings | `org_iam_bindings.hcl` | Organisation-level IAM |
| | Folder IAM Bindings | `folder_iam_bindings.hcl` | Folder-level IAM |
| | Service Account | `service_account.hcl` | Service account creation |
| | Workload Identity | `workload_identity.hcl` | GKE Workload Identity bindings |
| **PKI** | Certificate Authority Service | `certificate_authority_service.hcl` | Private CA pools and certificates |
| | Certificate Manager | `certificate_manager.hcl` | TLS certificate provisioning |

## Template Structure

Every template follows the same pattern:

```hcl
terraform {
  source = "git::https://github.com/terraform-google-modules/module-name.git//path?ref=${include.base.locals.module_versions.module_key}"
}

inputs = {
  # Template-specific defaults
}
```

Templates access module versions and merged configuration via `include.base.locals`, provided by the `base.hcl` include.

## Usage

### Including a Template

Always include root, base (with `expose = true`), and the specific template:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "template_name" {
  path           = "${get_repo_root()}/_common/templates/template_name.hcl"
  merge_strategy = "deep"
}
```

### Accessing Merged Configuration

`base.hcl` reads and merges the full hierarchy (`common.hcl`, `account.hcl`, `env.hcl`, `project.hcl`, `region.hcl`):

```hcl
inputs = {
  project_id  = include.base.locals.merged.project_name
  region      = include.base.locals.region
  environment = include.base.locals.environment
  labels      = include.base.locals.standard_labels
}
```

### Variable Precedence

Configuration follows this order (highest to lowest):

1. Local `inputs` block overrides
2. Template default inputs
3. `project.hcl` -- project-specific settings
4. `region.hcl` -- regional settings
5. `env.hcl` -- environment settings
6. `account.hcl` -- account settings
7. `common.hcl` -- global defaults and module versions

### Environment Awareness

Templates automatically apply different defaults based on `environment_type`:

```hcl
locals {
  environment_config = {
    production     = { deletion_protection = true,  disk_type = "pd-ssd",      machine_type = "e2-standard-2" }
    non-production = { deletion_protection = false, disk_type = "pd-standard", machine_type = "e2-micro" }
  }
  selected_config = local.environment_config[local.environment_type]
}
```

## Best Practices

- Override template values in local `inputs` -- never modify templates directly
- Test template changes in non-production before promoting to production
- Keep module versions in `_common/common.hcl` only
- Follow the deployment order defined in each template's documentation
- Use Secret Manager for sensitive data -- never hardcode secrets

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Module version conflicts | Check `_common/common.hcl` for correct versions |
| Dependency resolution failures | Verify mock outputs match actual module outputs |
| Template override issues | Ensure input merging follows the correct precedence |

```bash
terragrunt validate
terragrunt plan
terragrunt hclfmt --terragrunt-check
```

## Recent Compatibility Notes

- **BigQuery (v10.1.0)**: Use `dataset_name` instead of `friendly_name`. Do not pass `environment_type`.
- **Cloud SQL (v26.2.1)**: Use `additional_databases`/`additional_users` instead of `databases`/`users`. Use `deletion_protection_enabled`. Flatten `maintenance_window` into individual `maintenance_window_*` variables.
- **Cloud Storage (v11.0.0)**: `names` output is a map, not an array. Use `dependency.bucket.outputs.name` for single buckets, `names_list[0]` for multiple.

## References

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [Google Cloud Terraform Modules](https://github.com/terraform-google-modules)
- [DRY Principle in Terragrunt](https://terragrunt.gruntwork.io/docs/features/keep-your-terragrunt-configuration-dry/)
