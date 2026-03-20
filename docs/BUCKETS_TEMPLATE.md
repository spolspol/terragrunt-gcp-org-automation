# Cloud Storage Buckets Template

The Cloud Storage template (`_common/templates/cloud_storage.hcl`) creates GCS buckets with standardised security, lifecycle, and environment-aware settings using the [terraform-google-cloud-storage](https://github.com/terraform-google-modules/terraform-google-cloud-storage) module (v11.0.0). Buckets are deployed in parallel with VPC networks, secrets, and BigQuery datasets after project creation.

## Naming Convention

Buckets follow the pattern: `{name_prefix}-{project_name}-{directory_name}`

Example: directory `backup-storage` in project `dev-02` with prefix `tg` produces `tg-dev-02-backup-storage`.

## Environment-Specific Defaults

| Setting | Production | Non-Production |
|---------|------------|----------------|
| `versioning_enabled` | true | true |
| `force_destroy` | false | true |
| `public_access_prevention` | enforced | enforced |
| `uniform_bucket_level_access` | true | true |
| `storage_class` | STANDARD | STANDARD |

## Lifecycle Rule Templates

The template provides three predefined lifecycle profiles:

| Profile | Rule | Age |
|---------|------|-----|
| `log_bucket` | Move to COLDLINE | 30 days |
| `log_bucket` | Delete | 90 days |
| `backup_bucket` | Move to NEARLINE | 30 days |
| `backup_bucket` | Move to COLDLINE | 90 days |
| `backup_bucket` | Move to ARCHIVE | 365 days |
| `temp_bucket` | Delete | 7 days |

## Directory Structure

```
live/non-production/development/platform/dp-dev-01/
└── europe-west2/
    └── buckets/
        └── compute-logs/          # Example: compute log storage
            └── terragrunt.hcl
```

## Usage

### Creating a New Bucket

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
    project_id               = try(dependency.project.outputs.project_id, "mock-project-id")
    location                 = local.region
    names                    = [local.bucket_name]
    storage_class            = "STANDARD"
    public_access_prevention = "enforced"
    randomize_suffix         = true
    environment_type         = include.base.locals.merged.environment_type

    versioning = { for name in [local.bucket_name] : lower(name) => true }
    force_destroy = {
      for name in [local.bucket_name] :
      lower(name) => include.base.locals.merged.environment_type == "production" ? false : true
    }
    bucket_policy_only = { for name in [local.bucket_name] : lower(name) => true }

    bucket_type = "temp_bucket"  # or "log_bucket", "backup_bucket"

    labels = merge(
      {
        component   = "storage"
        environment = include.base.locals.merged.environment
        purpose     = "my-purpose"
        region      = local.region
      },
      try(include.base.locals.merged.org_labels, {}),
      try(include.base.locals.merged.env_labels, {}),
      try(include.base.locals.merged.project_labels, {})
    )
  }
)
```

### Custom Lifecycle Rules

```hcl
lifecycle_rules = [
  {
    action    = { type = "SetStorageClass", storage_class = "NEARLINE" }
    condition = { age = 30 }
  },
  {
    action    = { type = "Delete" }
    condition = { age = 365 }
  }
]
```

### Retention Policy (Compliance)

```hcl
retention_policy = {
  is_locked        = true
  retention_period = 2555000  # ~7 years in seconds
}
```

## Storage Classes

| Class | Use Case | Access Pattern |
|-------|----------|----------------|
| `STANDARD` | Frequently accessed data | Immediate |
| `NEARLINE` | Monthly access | ~1 second |
| `COLDLINE` | Quarterly access | ~1 second |
| `ARCHIVE` | Yearly access | ~12 hours |

## Deployment Order

Buckets deploy as part of step 3 in the pipeline:

1. Folder
2. Project
3. VPC Network + External IPs + **Buckets** + Secrets (parallel)
4. Compute, databases, and other resources

## Best Practices

- Use descriptive directory names that reflect the bucket's purpose
- Always define lifecycle rules for cost optimisation
- Use `randomize_suffix = true` for globally unique bucket names
- Enable versioning for important data buckets
- Let the template handle environment-specific settings (`force_destroy`, `deletion_protection`)

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Bucket name conflicts | Enable `randomize_suffix = true` for global uniqueness |
| Permission errors | Ensure the service account has Storage Admin roles |
| Lifecycle rule errors | Validate storage class transition order (STANDARD > NEARLINE > COLDLINE > ARCHIVE) |
| Output reference errors | Use `dependency.bucket.outputs.name` for single buckets, `names_list[0]` for multiple (`names` is a map in v11.0.0) |

## References

- [terraform-google-cloud-storage module](https://github.com/terraform-google-modules/terraform-google-cloud-storage)
- [Google Cloud Storage documentation](https://cloud.google.com/storage/docs)
