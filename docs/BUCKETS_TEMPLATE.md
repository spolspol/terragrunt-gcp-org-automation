# Cloud Storage Buckets Template Guide

This guide explains how to use the Cloud Storage buckets template (`_common/templates/cloud_storage.hcl`) to create and manage Google Cloud Storage buckets in a standardized way.

## Overview

The Cloud Storage template provides:
- Standardized bucket configurations with environment-specific settings
- Predefined lifecycle rules for different bucket types
- Security best practices (uniform bucket-level access, public access prevention)
- Template module versioning compatibility (v11.0.0+)

## Directory Structure

Buckets are organized under the regional directory with a clear naming pattern:

```
europe-west2/
└── buckets/
    ├── backup-storage/          # Long-term backup storage
    ├── data-processing/         # Temporary data processing
    ├── terraform-state/         # Terraform state files
    └── vm-scripts/              # VM startup and operational scripts
```

## Naming Convention

Buckets follow the naming pattern: `{name_prefix}-{project_name}-{directory_name}`

**Example:**
- Directory: `backup-storage`
- Project: `dev-02`
- Prefix: `tg`
- Bucket name: `tg-dev-02-backup-storage`

## Template Features

### Environment-Specific Configuration

The template automatically adapts settings based on `environment_type`:

| Setting | Production | Non-Production |
|---------|------------|----------------|
| `versioning_enabled` | ✅ true | ✅ true |
| `force_destroy` | ❌ false | ✅ true |
| `public_access_prevention` | ✅ enforced | ✅ enforced |
| `uniform_bucket_level_access` | ✅ true | ✅ true |
| `storage_class` | STANDARD | STANDARD |

### Predefined Lifecycle Rules

The template includes three lifecycle rule templates:

#### 1. Log Bucket Rules
```hcl
bucket_type = "log_bucket"
```
- **30 days**: Move to COLDLINE storage
- **90 days**: Delete objects

#### 2. Backup Bucket Rules
```hcl
bucket_type = "backup_bucket"
```
- **30 days**: Move to NEARLINE storage
- **90 days**: Move to COLDLINE storage
- **365 days**: Move to ARCHIVE storage

#### 3. Temporary Bucket Rules
```hcl
bucket_type = "temp_bucket"
```
- **7 days**: Delete objects

### Security Features

- **Uniform bucket-level access**: Enabled by default
- **Public access prevention**: Enforced
- **Bucket policy only**: Enabled for IAM-only access control
- **Encryption**: Uses Google-managed encryption keys by default

## Creating a New Bucket

### Step 1: Create Directory Structure

```bash
mkdir -p live/non-production/development/dev-01/europe-west2/buckets/my-new-bucket
```

### Step 2: Create terragrunt.hcl

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "bucket_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_storage.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs = true
}

locals {
  name_prefix = include.base.locals.merged.name_prefix != "" ? include.base.locals.merged.name_prefix : "tg"
  bucket_name = "${local.name_prefix}-${include.base.locals.merged.project_name}-my-new-bucket"
  region      = include.base.locals.region
}

inputs = merge(
  read_terragrunt_config("${get_repo_root()}/_common/templates/cloud_storage.hcl").inputs,
  {
    project_id = try(dependency.project.outputs.project_id, "mock-project-id")
    location   = local.region
    names      = [local.bucket_name]

    # Bucket-specific configuration
    storage_class            = "STANDARD"
    public_access_prevention = "enforced"
    randomize_suffix         = true
    environment_type         = include.base.locals.merged.environment_type

    # Environment-specific settings in map format
    versioning = {
      for name in [local.bucket_name] :
      lower(name) => true
    }
    force_destroy = {
      for name in [local.bucket_name] :
      lower(name) => include.base.locals.merged.environment_type == "production" ? false : true
    }
    bucket_policy_only = {
      for name in [local.bucket_name] :
      lower(name) => true
    }

    # Choose lifecycle rule template
    bucket_type = "temp_bucket"  # or "log_bucket", "backup_bucket"

    # Custom labels
    labels = merge(
      {
        component        = "storage"
        environment      = include.base.locals.merged.environment
        environment_type = include.base.locals.merged.environment_type
        name_prefix      = local.name_prefix
        purpose          = "my-purpose"
        region           = local.region
      },
      try(include.base.locals.merged.org_labels, {}),
      try(include.base.locals.merged.env_labels, {}),
      try(include.base.locals.merged.project_labels, {})
    )
  }
)
```

## Configuration Options

### Storage Classes

| Class | Use Case | Cost | Access Speed |
|-------|----------|------|--------------|
| `STANDARD` | Frequently accessed data | Highest | Immediate |
| `NEARLINE` | Monthly access | Medium | ~1 second |
| `COLDLINE` | Quarterly access | Lower | ~1 second |
| `ARCHIVE` | Yearly access | Lowest | ~12 hours |

### Lifecycle Rules

You can define custom lifecycle rules:

```hcl
lifecycle_rules = [
  {
    action = {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition = {
      age = 30
    }
  },
  {
    action = {
      type = "Delete"
    }
    condition = {
      age = 365
    }
  }
]
```

### IAM Configuration

```hcl
iam_members = [
  {
    role   = "roles/storage.objectViewer"
    member = "serviceAccount:my-service@project.iam.gserviceaccount.com"
  },
  {
    role   = "roles/storage.objectCreator"
    member = "serviceAccount:my-service@project.iam.gserviceaccount.com"
  }
]
```

### Retention Policy

For compliance requirements:

```hcl
retention_policy = {
  is_locked        = true
  retention_period = 2555000  # 7 years in seconds
}
```

## Current Bucket Configurations

### backup-storage
- **Purpose**: Long-term backup storage
- **Storage Class**: NEARLINE (cost-optimized for backups)
- **Lifecycle**: Moves to COLDLINE after 30 days, ARCHIVE after 90 days
- **Retention**: 7 years locked retention policy
- **Special Features**: More restrictive IAM for backup security

### data-processing
- **Purpose**: Temporary data processing
- **Storage Class**: STANDARD (for frequent access)
- **Lifecycle**: Custom rules for temporary data cleanup
- **Use Case**: ETL processes, data transformations

### terraform-state
- **Purpose**: Terraform state file storage
- **Storage Class**: STANDARD (for consistent access)
- **Versioning**: Always enabled for state history
- **Special Features**: Enhanced security for infrastructure state


### vm-scripts
- **Purpose**: Centralized storage for VM startup and operational scripts
- **Storage Class**: STANDARD (for immediate access during VM startup)
- **Versioning**: Enabled to track script changes
- **Structure**: Organized by VM type (e.g., `/web-server-01/`, `/app-server-01/`)
- **Special Features**: 
  - Automatic synchronization via GitHub Actions workflow
  - Scripts downloaded by VMs during startup via bootstrap script
  - Supports modular script architecture for easier maintenance
- **Security**: Restricted access to VM service accounts only

## Dependencies

Buckets depend on:
- **Project**: The GCP project where buckets are created
- **Regional Configuration**: For location and regional settings

## Deployment Order

Buckets are deployed as part of step 3-4 in the deployment pipeline:
1. Folder → 2. Project → 3. VPC Network + External IPs + **Buckets** + Secrets → 4. Other resources

## CI/CD Integration

- **Path Filters**: `live/**/buckets/**` and `_common/templates/cloud_storage.hcl`
- **Workflow Support**: Full validation and deployment automation
- **Parallel Deployment**: Buckets deploy in parallel with VPC networks and secrets

## Best Practices

1. **Naming**: Use descriptive directory names that reflect bucket purpose
2. **Lifecycle Rules**: Always define appropriate lifecycle rules for cost optimization
3. **Labels**: Include comprehensive labels for resource management
4. **Security**: Use uniform bucket-level access and prevent public access
5. **Versioning**: Enable versioning for important data buckets
6. **Environment Awareness**: Let the template handle environment-specific settings

## Troubleshooting

### Common Issues

1. **Bucket name conflicts**: Use `randomize_suffix = true` for globally unique names
2. **Permission errors**: Ensure the service account has Storage Admin roles
3. **Lifecycle rule errors**: Validate rule syntax and storage class transitions
4. **Force destroy**: Set appropriately based on environment type

### Template Version Compatibility

This template is compatible with:
- **terraform-google-cloud-storage**: v11.0.0+
- **Terragrunt**: 0.53.0+
- **OpenTofu**: 1.6.0+

The template handles the map-based input format required by newer module versions.
