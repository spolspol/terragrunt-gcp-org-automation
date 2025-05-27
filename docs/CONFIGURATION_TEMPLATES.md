# Configuration Templates

This document outlines the configuration templates available in the Terragrunt GCP infrastructure and how to use them.

## Overview

Configuration templates provide reusable, standardized configurations for common GCP resources. They help ensure consistent resource deployment across environments while reducing code duplication and maintaining DRY (Don't Repeat Yourself) principles.

Benefits of using templates:
- Consistent resource configuration across environments
- Simplified configuration management
- Centralized best practices enforcement
- Reduced chance of configuration errors
- Easier updates and maintenance

## Available Templates

| Template | Description | Path |
|----------|-------------|------|
| Project | GCP project creation and configuration | `_common/templates/project.hcl` |
| Folder | GCP folder creation and IAM management | `_common/templates/folder.hcl` |
| Network | VPC network, subnets, and firewall rules | `_common/templates/network.hcl` |
| Private Service Access | Private service connectivity setup | `_common/templates/private_service_access.hcl` |
| Secret Manager | Secret management and access control | `_common/templates/secret_manager.hcl` |
| Compute Instance | VM instances with instance templates | `_common/templates/compute_instance.hcl` |
| Instance Template | Reusable VM instance templates | `_common/templates/instance_template.hcl` |
| BigQuery | Dataset and table management | `_common/templates/bigquery.hcl` |
| Cloud Storage | GCS bucket creation and lifecycle management | `_common/templates/cloud_storage.hcl` |
| Cloud SQL | MSSQL 2022 Web Edition instances | `_common/templates/cloud_sql.hcl` |
| GKE | Google Kubernetes Engine clusters | `_common/templates/gke.hcl` |

## Template Structure

Each template follows a consistent structure:

```hcl
# Module source and version
terraform {
  source = "git::https://github.com/terraform-google-modules/module-name.git//path?ref=${local.module_versions.module_name}"
}

# Local variables for configuration
locals {
  module_versions = read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals.module_versions
  # Additional template-specific locals
}

# Default inputs
inputs = {
  # Template-specific default values
}
```

## Common Patterns

### Environment Awareness

Templates automatically apply different configurations based on environment type:

```hcl
locals {
  environment_config = {
    production = {
      deletion_protection = true
      disk_type = "pd-ssd"
      machine_type = "e2-standard-2"
    }
    non-production = {
      deletion_protection = false
      disk_type = "pd-standard"
      machine_type = "e2-micro"
    }
  }
  
  selected_config = local.environment_config[local.environment_type]
}

### Module Versioning

All templates use centralized module versioning from `_common/common.hcl`:

```hcl
locals {
  module_versions = read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals.module_versions
}

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-project-factory.git//modules/core_project_factory?ref=${local.module_versions.project_factory}"
}
```

### Dependency Management

Templates include mock outputs for dependency validation:

```hcl
dependency "vpc-network" {
  config_path = "../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock-project/global/networks/mock-vpc"
    subnets_self_links = ["projects/mock-project/regions/region/subnetworks/mock-subnet"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

## Usage Guidelines

### Including Templates

Always include the root configuration and the specific template:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "template_name" {
  path = "${get_parent_terragrunt_dir()}/_common/templates/template_name.hcl"
}
```

### Merging Configuration

Merge template inputs with local configuration:

```hcl
locals {
  merged_vars = merge(
    read_terragrunt_config(find_in_parent_folders("account.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("env.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("project.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals
  )
}

inputs = merge(
  read_terragrunt_config("${get_parent_terragrunt_dir()}/_common/templates/template_name.hcl").inputs,
  local.merged_vars,
  {
    # Custom configuration overrides
  }
```

### Variable Hierarchy

Configuration follows this precedence (highest to lowest):
1. Local `inputs` block overrides
2. Template default inputs
3. Common configuration from `_common/common.hcl`
4. Project-specific configuration from `project.hcl`
5. Environment configuration from `env.hcl`
6. Account configuration from `account.hcl`

## Best Practices

### Template Usage

1. **Always Use Templates** - Use templates for all standard GCP resources
2. **Don't Modify Templates Directly** - Override values in your local configuration
3. **Version Control** - Keep template modifications in version control
4. **Testing** - Test template changes in non-production environments first

### Configuration Management

1. **Consistent Naming** - Follow naming conventions defined in templates
2. **Environment Separation** - Use environment-specific configurations
3. **Label Everything** - Apply consistent labels for resource management
4. **Dependency Order** - Follow the deployment order defined in templates

### Security

1. **No Hardcoded Secrets** - Use Secret Manager for sensitive data
2. **Least Privilege** - Apply minimal necessary permissions
3. **Environment Isolation** - Separate production and non-production resources
4. **Audit Trails** - Enable logging and monitoring for all resources

## Template Development

### Creating New Templates

When creating new templates:

1. Follow the established structure pattern
2. Include environment-aware configurations
3. Add comprehensive mock outputs for dependencies
4. Document all input parameters and outputs
5. Include validation and testing examples

### Template Updates

When updating existing templates:

1. Maintain backward compatibility when possible
2. Update documentation for any new parameters
3. Test changes across all environments
4. Communicate changes to users

## Troubleshooting

### Common Issues

1. **Module Version Conflicts**
   - Check `_common/common.hcl` for correct module versions
   - Ensure all templates use the same module version reference

2. **Dependency Resolution Failures**
   - Verify mock outputs match actual module outputs
   - Check dependency paths are correct

3. **Template Override Issues**
   - Ensure input merging follows the correct precedence
   - Check for conflicting variable names

### Validation

Always validate templates with:

```bash
# Validate configuration
terragrunt validate

# Plan deployment
terragrunt plan

# Check formatting
terragrunt hclfmt --terragrunt-check
```

## Recent Updates

### BigQuery Template Updates
- Changed `friendly_name` to `dataset_name` for compatibility with terraform-google-bigquery v10.1.0
- Removed support for `environment_type` parameter as it's not accepted by the module
- Updated examples and documentation to reflect correct variable usage

### Cloud SQL Template Updates  
- Updated variable names for terraform-google-sql-db v15.0.0 compatibility:
  - `databases` → `additional_databases`
  - `users` → `additional_users`
  - `deletion_protection` → `deletion_protection_enabled`
- Removed unsupported variables: `edition`, `settings`, `insights_config`
- Flattened `maintenance_window` object into individual `maintenance_window_*` variables
- Fixed user configuration to require all three fields: `name`, `password`, `random_password`
- Updated backup configuration structure for proper SQL Server support

### Bucket Dependency Fixes
- Corrected bucket module output references from array notation to proper output names
- For single bucket configurations: use `dependency.bucket.outputs.name`
- For multiple buckets: use `dependency.bucket.outputs.names_list[0]` (not `names[0]`)
- The `names` output is a map, not an array, in terraform-google-cloud-storage v11.0.0

## References

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google Cloud Terraform Modules](https://github.com/terraform-google-modules)
- [DRY Principle in Terragrunt](https://terragrunt.gruntwork.io/docs/features/keep-your-terragrunt-configuration-dry/)
