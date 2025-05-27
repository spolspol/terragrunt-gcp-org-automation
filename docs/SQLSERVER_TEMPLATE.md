# SQL Server Template Guide

This document provides detailed information about SQL Server deployments in the Terragrunt GCP infrastructure, covering both Cloud SQL and compute-based approaches.

## Overview

This infrastructure supports two SQL Server deployment approaches:

### 1. Cloud SQL (Managed Database Service)
Uses Google Cloud SQL with a **multi-level, environment-driven pattern** for Microsoft SQL Server instances. Each configuration level can define a `sqlserver_settings` map, keyed by `environment_type`. This ensures DRY, maintainable, and environment-aware configuration using the [terraform-google-sql-db mssql submodule](https://github.com/terraform-google-modules/terraform-google-sql-db/tree/main/modules/mssql).

### 2. Compute-based SQL Server (Infrastructure-as-a-Service)
Uses compute instances with pre-installed SQL Server images for scenarios requiring more control over the SQL Server installation, custom configurations, or specific licensing requirements. This approach uses the compute instance template pattern with dedicated service accounts for enhanced security.

## Features

- **MSSQL 2022 Web Edition**: Standardized on Web edition for cost-effectiveness
- **Single Instance Design**: Structured for one primary Cloud SQL instance
- **Environment-aware sizing**: Production vs. non-production configurations
- **Private networking**: Secure VPC-only connectivity via Private Service Access
- **Template location**: `_common/templates/cloud_sql.hcl`
- **Standardized naming**: Directory-based naming convention
- **SSL/TLS required**: Encrypted connections enforced
- **Automated backups**: Environment-specific backup retention
- Integration with private service access for secure connectivity

## Configuration Pattern

### 1. Define `sqlserver_settings` at any level

Example in `_common/common.hcl`:
```hcl
locals {
  sqlserver_settings = {
    production = {
      edition = "ENTERPRISE"
      database_version = "SQLSERVER_2022_WEB"
      tier = "db-custom-4-15360"
      availability_type = "ZONAL"
      disk_size = 32
      disk_type = "PD_SSD"
      disk_autoresize = true
      disk_autoresize_limit = 512
      backup_configuration = {
        enabled            = true
        binary_log_enabled = false   # Required by module, ignored for SQL Server
        start_time         = "00:00"
        retention_days     = 30
        point_in_time_recovery_enabled = true
        retained_backups = 7
        retention_unit = "COUNT"
        transaction_log_retention_days = 7
      }
      maintenance_window = {
        day          = 7  # Sunday
        hour         = 2  # 2 AM
        update_track = "stable"
      }
      deletion_protection = true
    }
    non-production = {
      edition = "ENTERPRISE"
      database_version = "SQLSERVER_2022_WEB"
      tier = "db-custom-1-3584"
      disk_size = 16
      disk_type = "PD_SSD"
      disk_autoresize = true
      disk_autoresize_limit = 64
      backup_configuration = {
        enabled            = true
        binary_log_enabled = true   # Required by module, ignored for SQL Server
        start_time         = "02:00"
        retention_days     = 7
        point_in_time_recovery_enabled = true
        retained_backups = 7
        retention_unit = "COUNT"
        transaction_log_retention_days = 7
      }
      maintenance_window = {
        day          = 6  # Saturday
        hour         = 2  # 2 AM
        update_track = "stable"
      }
      deletion_protection = false
    }
  }
}
```

### 2. Basic Implementation

```hcl
include {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "project" {
  path = find_in_parent_folders("project.hcl")
}

include "region" {
  path = find_in_parent_folders("region.hcl")
}

include "common" {
  path = "${get_terragrunt_dir()}/../../../../../../_common/common.hcl"
}

include "sqlserver_template" {
  path = "${get_terragrunt_dir()}/../../../../../../_common/templates/sqlserver.hcl"
}

dependency "vpc-network" {
  config_path = "../../vpc-network"
  mock_outputs = {
    network_name            = "default"
    network_self_link       = "projects/mock-project/global/networks/default"
    subnets_self_links      = ["projects/mock-project/regions/region/subnetworks/default"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "private_service_access" {
  config_path = "../../private-service-access"
  mock_outputs = {
    google_compute_global_address_name = "mock-private-ip-range"
    address                            = "10.11.0.0"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config("${get_terragrunt_dir()}/../../../../../../_common/common.hcl")
  
  merged_vars  = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )
  
  name_prefix = local.merged_vars.name_prefix != "" ? local.merged_vars.name_prefix : "org"
  selected_env_config = lookup(local.merged_vars.sqlserver_settings, local.merged_vars.environment_type, {})
}

inputs = merge(
  read_terragrunt_config("${get_terragrunt_dir()}/../../../../../../_common/templates/sqlserver.hcl").inputs,
  local.merged_vars,
  local.selected_env_config,
  {
    name        = replace("${local.name_prefix}-${local.merged_vars.project}-sqlserver-01", "_", "-")
    project_id  = dependency.project.outputs.project_id
    region      = local.merged_vars.region
    environment_type = local.merged_vars.environment_type

    # Use private networking for SQL Server with private service access
    ip_configuration = merge(
      try(local.selected_env_config.ip_configuration, {}),
      {
        private_network     = dependency.vpc-network.outputs.network_self_link
        require_ssl         = true
        ipv4_enabled        = false
        allocated_ip_range  = dependency.private_service_access.outputs.google_compute_global_address_name
        authorized_networks = []
      }
    )
    
    # Database configuration
    databases = [
      {
        name      = "main"
        charset   = "UTF8"
        collation = "SQL_Latin1_General_CP1_CI_AS"
      },
      {
        name      = "reporting"
        charset   = "UTF8"
        collation = "SQL_Latin1_General_CP1_CI_AS"
      }
    ]

    # Resource Labels
    user_labels = merge(
      {
        component   = "sqlserver"
        environment = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
        name_prefix = local.name_prefix
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)
```

### 3. Required and Recommended Keys

The following keys are required in each environment's `backup_configuration` block (even if not used by SQL Server, the module requires them):
- `enabled`
- `binary_log_enabled` (set to `true` or `false`, ignored for SQL Server)
- `start_time`
- `retention_days`
- `point_in_time_recovery_enabled` (set to `true` or `false`)
- `retained_backups`
- `retention_unit`
- `transaction_log_retention_days`

**Recommended:**
- `database_version` (set to `SQLSERVER_2022_WEB` for latest features and support)
- `edition` (e.g., `ENTERPRISE`)
- `tier` (choose an appropriate machine type for your workload)

## Directory Structure

The SQL Server module is typically placed at the regional level:

```
live/
├── account/
│   └── environment/
│       └── project-name/
│           ├── project/
│           │   └── terragrunt.hcl  # Project creation
│           ├── vpc-network/
│           │   ├── terragrunt.hcl  # VPC network creation
│           │   └── private-service-access/
│           │       └── terragrunt.hcl  # Private service access
│           └── region/
│               ├── sqlserver/
│               │   └── terragrunt.hcl  # SQL Server instance
│               └── ...  # Other regional resources
```

## Integration with Other Modules

### VPC Network Integration

```hcl
dependency "vpc-network" {
  config_path = "../../vpc-network"
  mock_outputs = {
    network_name            = "default"
    network_self_link       = "projects/mock-project/global/networks/default"
    subnets_self_links      = ["projects/mock-project/regions/region/subnetworks/default"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

### Private Service Access Integration

```hcl
dependency "private_service_access" {
  config_path = "../../private-service-access"
  mock_outputs = {
    google_compute_global_address_name = "mock-private-ip-range"
    address                            = "10.11.0.0"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

### Project Integration

```hcl
dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

## Environment-Specific Configuration

The SQL Server settings are automatically selected based on the `environment_type`:

### Production Environment
- **Edition**: ENTERPRISE
- **Tier**: db-custom-4-15360 (4 vCPUs, 15GB RAM)
- **Disk**: 32GB PD_SSD with autoresize up to 512GB
- **Backup**: 30-day retention, daily backups
- **Maintenance**: Sunday 2 AM
- **Deletion Protection**: Enabled

### Non-Production Environment
- **Edition**: ENTERPRISE
- **Tier**: db-custom-1-3584 (1 vCPU, 3.5GB RAM)
- **Disk**: 16GB PD_SSD with autoresize up to 64GB
- **Backup**: 7-day retention, daily backups
- **Maintenance**: Saturday 2 AM
- **Deletion Protection**: Disabled

## Best Practices

1. **Define only the environments you need** at each level; the merge pattern ensures the most specific config wins
2. **Always include all required keys** in `backup_configuration` (even if not used by SQL Server)
3. **Set `database_version` to `SQLSERVER_2022_WEB`** for new deployments unless you have a specific need for an older version
4. **Use top-level keys** for all SQL Server module inputs; do not nest under `settings`
5. **Use the merge pattern** for DRY, maintainable, and environment-aware configuration
6. **Use labels** for cost allocation and resource tracking
7. **Always use private networking** for production workloads
8. **Plan dependencies carefully** - ensure VPC network and private service access are created first\n9. **Use correct variable names** - Use `additional_databases` instead of `databases` and `additional_users` instead of `users`\n10. **Password configuration** - Always provide both `password` and `random_password` fields for users\n11. **Maintenance windows** - Use individual `maintenance_window_*` variables instead of nested objects\n12. **Deletion protection** - Use `deletion_protection_enabled` instead of `deletion_protection`

## Security Configuration

The implementation follows security best practices:

1. **Private IP Only**: `ipv4_enabled = false` disables public IP access
2. **SSL Required**: `require_ssl = true` enforces encrypted connections
3. **VPC Integration**: Uses private service access for secure connectivity
4. **No Authorized Networks**: Empty `authorized_networks` list for maximum security

## Advanced Configuration

### Custom Database Flags

```hcl
inputs = merge(
  # ... other configuration ...
  {
    database_flags = [
      {
        name  = "remote access"
        value = "on"
      },
      {
        name  = "contained database authentication"
        value = "on"
      },
      {
        name  = "cross db ownership chaining"
        value = "off"
      }
    ]
  }
)
```

### High Availability Configuration

```hcl
inputs = merge(
  # ... other configuration ...
  {
    availability_type = "REGIONAL"  # For high availability
    backup_location   = "region"
  }
)
```

## Troubleshooting

### Common Issues

1. **Missing required attributes**
   - Ensure all required keys are present in each environment's config, especially in `backup_configuration`
   - Check that `binary_log_enabled` and `point_in_time_recovery_enabled` are set (even though ignored for SQL Server)

2. **Wrong config applied**
   - Check the merge order and that your `environment_type` is set correctly at the env level
   - Verify the `selected_env_config` lookup is finding the correct environment

3. **Private networking issues**
   - Ensure VPC network and private service access are deployed before SQL Server
   - Check that the `allocated_ip_range` matches the private service access output

4. **API errors**
   - Ensure all required GCP APIs are enabled:
     - `sqladmin.googleapis.com`
     - `servicenetworking.googleapis.com`
     - `compute.googleapis.com`
   - Verify the service account has the correct roles:
     - `roles/cloudsql.admin`
     - `roles/compute.networkAdmin`

5. **Dependency issues**
   - Ensure proper dependency ordering: project → VPC network → private service access → SQL Server
   - Check mock outputs match the actual module outputs

6. **Unused input warnings**
   - Remove deprecated variables: `edition`, `settings`, `insights_config`
   - Use `additional_databases` instead of `databases`
   - Use `additional_users` instead of `users` 
   - Use `deletion_protection_enabled` instead of `deletion_protection`
   - Flatten `maintenance_window` object into individual variables

7. **User configuration errors**
   - Ensure each user has `name`, `password`, and `random_password` fields
   - Set `password = ""` when using `random_password = true`
   - Do not include `host` field for MSSQL (MySQL only)

### Validation Commands

```bash
# List SQL instances
gcloud sql instances list --project=PROJECT_ID

# Describe a specific instance
gcloud sql instances describe INSTANCE_NAME --project=PROJECT_ID

# Check private service access
gcloud services vpc-peerings list --network=NETWORK_NAME --project=PROJECT_ID

# Verify connectivity (from a VM in the same VPC)
sqlcmd -S PRIVATE_IP_ADDRESS -U USERNAME -P PASSWORD
```

## Module Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `instance_name` | Name of the SQL Server instance | `"org-project-sqlserver-01"` |
| `private_ip_address` | Private IP address | `"10.11.0.5"` |
| `connection_name` | Connection name for applications | `"project:region:instance"` |

## Compute-based SQL Server Implementation

### Instance Template Configuration

Compute-based SQL Server instances use the instance template pattern with dedicated service accounts:

```hcl
include "instance_template" {
  path = "${get_repo_root()}/_common/templates/instance_template.hcl"
}

inputs = {
  # Create a dedicated service account for this instance
  create_service_account = true
  service_account = null
  
  # SQL Server image configuration
  source_image         = "sql-2019-web-windows-2025-dc-v20250612"
  source_image_project = "windows-sql-cloud"
  
  # Machine configuration based on environment
  machine_type = try(local.selected_env_config.machine_type, "n2-standard-2")
  
  # Additional disks for SQL Server data and logs
  additional_disks = [
    {
      disk_name             = "data-disk"
      device_name           = "data-disk"
      disk_size_gb          = 3027
      disk_type             = "pd-standard"
      disk_autoresize       = true
      disk_autoresize_limit = 3584
      auto_delete           = false
      labels = {
        type = "sqlserver-data"
      }
    },
    {
      disk_name             = "log-disk"
      device_name           = "log-disk"
      disk_size_gb          = 256
      disk_autoresize       = true
      disk_autoresize_limit = 512
      disk_type             = "pd-standard"
      auto_delete           = false
      labels = {
        type = "sqlserver-logs"
      }
    }
  ]
  
  # Windows startup script
  metadata = {
    windows-startup-script-ps1 = templatefile("${get_terragrunt_dir()}/startup-script.ps1", {
      # Script variables...
    })
  }
}
```

### IAM Bindings for Compute SQL Server

Create `iam-bindings/terragrunt.hcl` for the SQL Server instance:

```hcl
include "iam_template" {
  path = "${get_repo_root()}/_common/templates/iam_bindings.hcl"
}

dependency "instance_template" {
  config_path = "../"
  mock_outputs = {
    service_account_info = {
      email = "mock-sql-server@mock-project-id.iam.gserviceaccount.com"
    }
  }
}

inputs = {
  projects = [dependency.project.outputs.project_id]
  mode     = "additive"

  bindings = {
    # Access to SQL Server admin/DBA passwords
    "roles/secretmanager.secretAccessor" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]

    # Access to backup storage bucket
    "roles/storage.objectAdmin" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]

    # Monitoring and logging
    "roles/logging.logWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]

    "roles/monitoring.metricWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
  }
}
```

### Directory Structure for Compute SQL Server

```
compute/
└── sql-server-01/
    ├── terragrunt.hcl              # Instance template
    ├── iam-bindings/
    │   └── terragrunt.hcl          # IAM bindings
    ├── vm/
    │   └── terragrunt.hcl          # Compute instance
    └── startup-script.ps1          # Windows startup script
```

### Available SQL Server Images

Common SQL Server images available in the `windows-sql-cloud` project:

- `sql-2019-web-windows-2025-dc-v20250612` - SQL Server 2019 Web on Windows Server 2025
- `sql-2022-web-windows-2025-dc-v20250515` - SQL Server 2022 Web on Windows Server 2025
- `sql-2019-standard-windows-2025-dc-v20250612` - SQL Server 2019 Standard on Windows Server 2025
- `sql-2022-standard-windows-2025-dc-v20250515` - SQL Server 2022 Standard on Windows Server 2025

### Security Configuration for Compute SQL Server

1. **Dedicated Service Account**: Each SQL Server instance gets its own service account
2. **Secret Management**: Database passwords stored in Google Secret Manager
3. **Network Security**: Instances connected to private VPC with firewall rules
4. **Disk Encryption**: All disks encrypted at rest by default
5. **Windows Security**: OS login disabled, custom admin accounts configured

### Deployment Order for Compute SQL Server

1. **Project** → Creates the GCP project
2. **VPC Network** → Creates the network infrastructure  
3. **Secrets** → Creates SQL Server admin/DBA password secrets
4. **Buckets** → Creates backup storage bucket
5. **Instance Template** → Creates the template and service account
6. **IAM Bindings** → Grants permissions to the service account
7. **Compute Instance** → Creates the SQL Server VM

## Cloud SQL Implementation

### Instance Structure

The current Cloud SQL implementation follows a single-instance pattern:

```
cloud-sql/
└── sql-server-main/       # MSSQL 2022 Web Edition instance
    └── terragrunt.hcl     # Instance configuration
```

### Instance Configuration

The `sql-server-main` instance is configured with:

- **Database Engine**: Microsoft SQL Server 2022 Web Edition
- **Network**: Private IP only (no public IP) via Private Service Access
- **Security**: SSL/TLS required for all connections
- **Databases**: 
  - `main` - Primary application database
  - `reporting` - Reporting and analytics database

### Dependencies

The Cloud SQL instance depends on:
- **VPC Network** - for private IP connectivity
- **Private Service Access** - for VPC peering with Google services  
- **Project** - where the instance will be created

### Naming Convention

Instance name is automatically generated from the directory name with an optional prefix:
- Directory: `sql-server-main`
- Instance name: `tg-sql-server-main` (with default prefix "tg")

### Template Integration

The instance uses the Cloud SQL template from `_common/templates/cloud_sql.hcl` which provides:
- Environment-specific configuration inheritance
- Standardized security settings
- Automated backup configuration
- Performance optimization based on environment type

## Choosing Between Cloud SQL and Compute-based SQL Server

### Use Cloud SQL When:
- You want a fully managed database service
- You need automatic backups, patching, and maintenance
- You prefer pay-as-you-go licensing
- You want built-in high availability options
- You need automatic scaling capabilities

### Use Compute-based SQL Server When:
- You need specific SQL Server configurations not available in Cloud SQL
- You have existing SQL Server licenses to use (BYOL)
- You need full control over the SQL Server installation
- You require custom SQL Server features or third-party add-ons
- You need to run multiple SQL Server instances on the same machine

## References

- [terraform-google-sql-db mssql module](https://github.com/terraform-google-modules/terraform-google-sql-db/tree/main/modules/mssql)
- [terraform-google-vm module](https://github.com/terraform-google-modules/terraform-google-vm)
- [Google Cloud SQL for SQL Server documentation](https://cloud.google.com/sql/docs/sqlserver)
- [SQL Server on Google Cloud Compute Engine](https://cloud.google.com/sql-server)
- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/)
- [Private Service Access documentation](https://cloud.google.com/vpc/docs/private-service-access)
- [IAM Bindings Template Guide](IAM_BINDINGS_TEMPLATE.md)
- [Compute Template Guide](COMPUTE_TEMPLATE.md) 
