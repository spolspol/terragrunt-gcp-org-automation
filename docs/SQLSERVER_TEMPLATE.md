# SQL Server Template Guide

This document covers the two SQL Server deployment models available in the Terragrunt GCP infrastructure: Cloud SQL (managed) and compute-based (IaaS).

## Overview

| Aspect | Cloud SQL (Managed) | Compute-based (IaaS) |
|--------|-------------------|---------------------|
| Template | `_common/templates/cloud_sql.hcl` | `instance_template.hcl` + `compute_instance.hcl` |
| Module | `terraform-google-sql-db` (v26.2.1) | `terraform-google-vm` (v13.2.4) |
| Use case | Standard workloads, automatic patching | BYOL, custom config, third-party add-ons |
| Image | N/A (managed) | `sql-std-2022-win-2025` family |
| Networking | Private Service Access | VPC subnet with firewall rules |

Cloud SQL is the recommended path for most workloads. Use compute-based only when you need full OS-level control or existing licence reuse.

## Cloud SQL (Managed)

### How It Works

The `cloud_sql.hcl` template wraps the `terraform-google-sql-db//modules/mssql` submodule. Environment-specific sizing is driven by `sqlserver_settings` in `_common/common.hcl`, keyed by `environment_type` (production / non-production).

### Configuration

Settings are selected automatically at deploy time via a lookup:

```hcl
local.selected_env_config = lookup(
  include.base.locals.merged.sqlserver_settings,
  include.base.locals.merged.environment_type, {}
)
```

| Setting | Production | Non-Production |
|---------|-----------|---------------|
| Tier | db-custom-4-15360 | db-custom-1-3840 |
| Disk | 32 GB PD_SSD (max 512 GB) | 16 GB PD_SSD (max 64 GB) |
| Maintenance | Sunday 02:00 | Saturday 02:00 |
| Deletion protection | Enabled | Disabled |

### Usage

Create a directory under your project's regional path and include the template:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_sql" {
  path           = "${get_repo_root()}/_common/templates/cloud_sql.hcl"
  merge_strategy = "deep"
}

dependency "vpc-network" {
  config_path = "../../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock/global/networks/default"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "private_service_access" {
  config_path = "../../private-service-access"
  mock_outputs = {
    google_compute_global_address_name = "mock-range"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = { project_id = "mock-project" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = merge(
  include.base.locals.merged,
  local.selected_env_config,
  {
    name       = "${local.name_prefix}-${include.base.locals.merged.project}-sqlserver-01"
    project_id = dependency.project.outputs.project_id
    region     = include.base.locals.region

    ip_configuration = {
      private_network    = dependency.vpc-network.outputs.network_self_link
      require_ssl        = true
      ipv4_enabled       = false
      allocated_ip_range = dependency.private_service_access.outputs.google_compute_global_address_name
    }

    additional_databases = [
      { name = "main",      charset = "UTF8", collation = "SQL_Latin1_General_CP1_CI_AS" },
      { name = "reporting", charset = "UTF8", collation = "SQL_Latin1_General_CP1_CI_AS" }
    ]
  }
)
```

### Dependencies

Resources must exist before deploying Cloud SQL:

1. **Project** -- the GCP project
2. **VPC Network** -- private IP connectivity
3. **Private Service Access** -- VPC peering with Google services

## Compute-based Alternative

### How It Works

Compute-based SQL Server uses the standard two-step pattern (instance template then compute instance) with a Windows SQL Server image. Environment settings come from `compute_sqlserver_settings` in `_common/common.hcl`.

### Directory Structure

```
compute/
 sql-server-01/
   terragrunt.hcl          # Instance template (includes instance_template.hcl)
   vm/
     terragrunt.hcl        # Compute instance (includes compute_instance.hcl)
```

Live example: `live/non-production/development/platform/dp-dev-01/europe-west2/compute/sql-server-01/`

### Key Configuration Points

- **Image**: `sql-std-2022-win-2025` family from `windows-sql-cloud` project
- **Additional disks**: Separate data and log disks defined in `compute_sqlserver_settings`
- **Service account**: Dedicated per-instance (`create_service_account = true`)
- **Startup script**: PowerShell via `windows-startup-script-ps1` metadata key

### Deployment Order

Project --> VPC Network --> Secrets --> Buckets --> Instance Template --> IAM Bindings --> Compute Instance

## Best Practices

- Use `additional_databases` (not `databases`) and `additional_users` (not `users`) for the Cloud SQL module
- Use `deletion_protection_enabled` (not `deletion_protection`) -- module naming convention
- Flatten maintenance window into `maintenance_window_day`, `maintenance_window_hour`, `maintenance_window_update_track`
- Always deploy via private networking; keep `ipv4_enabled = false`
- Include all required `backup_configuration` keys even when values are ignored for MSSQL

## Troubleshooting

- **Unused input warnings** -- Remove deprecated variables (`edition`, `settings`, `deletion_protection`). Use the flat variable names the module expects.
- **Private networking failures** -- Ensure VPC and Private Service Access are deployed first. Verify `allocated_ip_range` matches PSA output.
- **Missing API errors** -- Enable `sqladmin.googleapis.com` and `servicenetworking.googleapis.com` on the project.
- **User config errors** -- Each user needs `name`, `password`, and `random_password`. Do not include `host` for MSSQL.
- **Dependency cycle** -- Follow the strict ordering: Project --> VPC --> PSA --> Cloud SQL.

## References

- [terraform-google-sql-db mssql module](https://github.com/terraform-google-modules/terraform-google-sql-db/tree/main/modules/mssql)
- [terraform-google-vm module](https://github.com/terraform-google-modules/terraform-google-vm)
- [Cloud SQL for SQL Server docs](https://cloud.google.com/sql/docs/sqlserver)
- [Private Service Access docs](https://cloud.google.com/vpc/docs/private-service-access)
- [Compute Template Guide](COMPUTE_TEMPLATE.md)
