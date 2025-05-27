# Module Versioning Strategy

This document outlines the approach to module versioning in the Terragrunt GCP infrastructure.

## Overview

All Terraform module versions are centrally defined in `_common/common.hcl` to ensure consistency across environments and resources. This approach provides several benefits:

- Single source of truth for module versions
- Simplified version upgrades
- Consistent module usage across environments
- Easy auditing of module versions in use

## Module Version Declaration

### Location

All module versions are declared in the `module_versions` map in `_common/common.hcl`:

```hcl
# In _common/common.hcl
locals {
  module_versions = {
    bigquery       = "v10.1.0"
    sql_db         = "v15.0.0"
    vm             = "v13.2.4"
    network        = "v6.0.1"
    gke            = "v28.0.0"
    iam            = "v7.7.1"
    secret_manager = "v0.8.0"
    # ... other modules
  }
}
```

### Usage in Terragrunt Files

To use these versions in your Terragrunt configurations:

1. Include the _common/common.hcl file:
```hcl
include "common" {
  path = "${get_parent_terragrunt_dir()}/_common/common.hcl"
}
```

2. Read the common variables:
```hcl
locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  
  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.common_vars.locals,
  )
}
```

3. Reference the module version in your source blocks:
```hcl
terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-sql-db.git//?ref=${local.merged_vars.module_versions.sql_db}"
}
```

## Version Upgrade Process

### When to Upgrade

- **Security Updates**: Immediately for critical security patches
- **Bug Fixes**: As needed when bugs affect your infrastructure
- **Feature Enhancements**: On a scheduled basis (quarterly review)
- **Major Versions**: Plan and test thoroughly before upgrading

### Upgrade Procedure

1. **Research**: Review the module's changelog for breaking changes
2. **Update**: Change the version in `_common/common.hcl` only
3. **Test**: Run `terragrunt plan` on non-production environments
4. **Stage**: Apply changes to dev/staging environments first
5. **Review**: Verify the changes work as expected
6. **Deploy**: Roll out to production during a maintenance window
7. **Document**: Update internal documentation with any changes

### Rollback Procedure

If an upgrade causes issues:

1. Revert the version in `_common/common.hcl` to the previous working version
2. Run `terragrunt plan` to verify the rollback plan
3. Apply the rollback to affected environments
4. Document the issue encountered for future reference

## Adding New Modules

When adding a new module:

1. Research available modules and select one with:
   - Active maintenance
   - Good documentation
   - Comprehensive examples
   - Appropriate license

2. Add the module to `_common/common.hcl`:
```hcl
module_versions = {
  # Existing modules...
  new_module = "v1.2.3"
}
```

3. Create a template in the `_common/templates/` directory if the module will be used in multiple places

4. Document usage examples in the module's README

## Version Pinning Strategy

We use semantic versioning with the following guidelines:

- **Major Versions** (`vX.0.0`): Pin to specific major version for stability
- **Minor Versions** (`v1.X.0`): Pin to specific minor version for consistent behavior
- **Patch Versions** (`v1.0.X`): Pin to specific patch version for maximum stability

Never use:
- `latest` - Unpredictable and can break unexpectedly
- Branch names - Can change without notice
- Commit hashes - Hard to track and audit

## Compliance and Auditing

The centralized version management enables:

1. Automated scanning for outdated modules
2. Compliance reports for security patches
3. Dependency drift detection
4. Clear audit trail for infrastructure changes

## Reference Examples

See these example implementations:

- SQL Server: `live/account/environment/region/sqlserver/terragrunt.hcl`
- BigQuery: `live/account/environment/region/bigquery/terragrunt.hcl`
- Secret Manager: `live/account/environment/secrets/secret-name/terragrunt.hcl`
