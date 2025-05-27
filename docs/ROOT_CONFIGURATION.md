# Root Configuration (root.hcl)

## Overview

This project uses a root configuration file named `root.hcl` instead of the default `terragrunt.hcl` at the repository root. This document explains the purpose of this file and how to use it properly in your Terragrunt configurations.

## Purpose

The root configuration file (`root.hcl`) serves several important purposes:

1. **Remote State Configuration**: Defines how and where Terraform state is stored
2. **Provider Configuration**: Generates consistent provider blocks for all child configurations
3. **Common Variables**: Establishes variables available to all modules
4. **Default Inputs**: Sets default values that can be overridden by child configurations
5. **Version Constraints**: Enforces consistent Terraform version usage

## Why `root.hcl` Instead of `terragrunt.hcl`?

Using a named root configuration file (`root.hcl`) instead of the default `terragrunt.hcl` provides several benefits:

1. **Clarity**: Explicitly shows that this is the root configuration
2. **Distinction**: Differentiates from regular module-level terragrunt.hcl files
3. **Intention**: Makes it clear when a configuration is including the root file
4. **Flexibility**: Allows for multiple root configurations if needed in the future

## How to Include the Root Configuration

In all child Terragrunt configurations, include the root configuration using:

```hcl
include {
  path = find_in_parent_folders("root.hcl")
}
```

This explicitly looks for the `root.hcl` file in parent directories, rather than the default behavior of looking for `terragrunt.hcl`.

## Root Configuration Contents

The `root.hcl` file contains:

1. **Remote State Configuration**:
   ```hcl
   remote_state {
     backend = "gcs"
     config = {
       bucket         = "my-terragrunt-state-bucket"
       prefix         = "${path_relative_to_include()}"
       project        = "my-gcp-project-id"
       location       = "us-central1"
     }
   }
   ```

2. **Provider Generation**:
   ```hcl
   generate "provider" {
     path      = "provider.tf"
     if_exists = "overwrite"
     contents  = <<EOF
   # Provider configuration blocks...
   EOF
   }
   ```

3. **Common Variable Definitions**:
   ```hcl
   generate "common_variables" {
     path      = "common_variables.tf"
     if_exists = "overwrite"
     contents  = <<EOF
   # Common variable definitions...
   EOF
   }
   ```

4. **Terraform Version Constraints**:
   ```hcl
   terraform {
     extra_arguments "common_vars" {
       # Arguments for Terraform commands...
     }
   }
   ```

## Best Practices

1. **Always Explicitly Include**: Always use `find_in_parent_folders("root.hcl")` instead of the default `find_in_parent_folders()`
2. **Include First**: The root include should be the first block in your configuration file
3. **Don't Duplicate**: Don't define settings in child configurations that are already in the root configuration
4. **Override Carefully**: When overriding settings from the root configuration, be explicit about what you're changing
