# Folder Template

This document provides detailed information about the Folder template available in the Terragrunt GCP infrastructure.

## Overview

The Folder template (`_common/templates/folder.hcl`) provides a standardized approach to deploying Google Cloud folders using the [terraform-google-folders](https://github.com/terraform-google-modules/terraform-google-folders) module. It ensures consistent folder structure, proper IAM setup, and environment-aware configuration.

## Features

- Environment-aware folder configuration
- Standardized folder naming conventions
- Hierarchical folder organization
- IAM management for folders
- Labeling for resource management
- Organization policy support

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `folder_name` | Name of the folder to create | `"dev-environment"` |
| `parent` | Parent resource (organization or folder) | `"organizations/123456789"` |

### Optional Parameters with Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `folder_iam_members` | `{}` | IAM members to assign to the folder |
| `folder_iam_roles` | `[]` | IAM roles to create bindings for |
| `org_policies` | `{}` | Organization policies to apply |
| `folder_labels` | See template | Resource labels |

## Directory Structure

Folder configurations are located within the environment directories following this pattern:

```
live/
└── non-production/
    └── development/
        └── folder/          # Folder configuration directory
            └── terragrunt.hcl
```

## Usage

### Basic Implementation

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "folder_template" {
  path           = "${get_repo_root()}/_common/templates/folder.hcl"
  merge_strategy = "deep"
}

inputs = {
  folder_name = "${include.base.locals.merged.name_prefix}-${include.base.locals.environment}"
  parent      = try(include.base.locals.merged.organization_id, "organizations/mock-org-id")

  # Folder IAM configuration
  folder_iam_members = {
    "roles/resourcemanager.folderAdmin" = [
      "group:devops@example.com"
    ]
    "roles/resourcemanager.folderViewer" = [
      "group:developers@example.com"
    ]
  }

  folder_labels = merge(
    include.base.locals.standard_labels,
    {
      component = "folder"
    }
  )
}
```

### Advanced Usage

#### Hierarchical Folder Structure

```hcl
inputs = merge(
  # ... other configuration ...
  {
    # Create nested folder structure
    folder_name = "${include.base.locals.merged.name_prefix}-${include.base.locals.environment}-workloads"
    parent      = "folders/123456789"  # Parent folder ID
    
    # Organization policies
    org_policies = {
      "constraints/compute.restrictLoadBalancerCreationForTypes" = {
        allow_all = false
        denied_values = ["EXTERNAL"]
      }
    }
  }
)
```

#### IAM Management

```hcl
inputs = merge(
  # ... other configuration ...
  {
    folder_iam_members = {
      "roles/resourcemanager.folderAdmin" = [
        "group:folder-admins@example.com",
        "serviceAccount:terraform@project.iam.gserviceaccount.com"
      ]
      "roles/resourcemanager.projectCreator" = [
        "group:project-creators@example.com"
      ]
      "roles/billing.user" = [
        "group:billing-users@example.com"
      ]
    }
  }
)
```

## Best Practices

1. **Hierarchical Organization** - Use folders to create logical separation between environments and teams
2. **Consistent Naming** - Use standardized naming conventions with organization prefix
3. **IAM Principle of Least Privilege** - Grant minimal necessary permissions
4. **Organization Policies** - Use policies to enforce security and compliance requirements
5. **Environment Separation** - Create separate folders for different environments
6. **Labeling** - Use comprehensive labels for organization and cost management

## Common Folder Hierarchy

```
Organization
├── shared-services/
│   ├── networking/
│   ├── security/
│   └── monitoring/
├── production/
│   ├── applications/
│   └── data/
├── development/
│   ├── applications/
│   └── data/
└── sandbox/
    └── experiments/
```

## Deployment Order

1. **Organization Setup** → Configure organization-level settings
2. **Root Folders** → Create top-level folders (production, development, etc.)
3. **Sub-folders** → Create application or team-specific folders
4. **Projects** → Create projects within folders

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure the service account has `roles/resourcemanager.folderCreator`
   - Check organization-level IAM permissions

2. **Parent Resource Not Found**
   - Verify the parent organization or folder ID
   - Ensure the parent resource exists

3. **Policy Constraint Violations**
   - Check for conflicting organization policies
   - Verify policy values are valid

### Validation Commands

```bash
# List folders
gcloud resource-manager folders list --organization=ORGANIZATION_ID

# Describe a folder
gcloud resource-manager folders describe FOLDER_ID

# List IAM policies for a folder
gcloud resource-manager folders get-iam-policy FOLDER_ID
```

## Module Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `folder_id` | ID of the created folder | `"folders/123456789"` |
| `folder_name` | Name of the created folder | `"dev-environment"` |
| `folder_parent` | Parent of the folder | `"organizations/123456789"` |

## Security Considerations

1. **IAM Reviews** - Regularly review and audit folder IAM permissions
2. **Organization Policies** - Implement and maintain appropriate security policies
3. **Access Logging** - Enable audit logging for folder-level changes
4. **Least Privilege** - Follow principle of least privilege for all access grants

## References

- [terraform-google-folders module](https://github.com/terraform-google-modules/terraform-google-folders)
- [Google Cloud Resource Manager documentation](https://cloud.google.com/resource-manager/docs)
- [Google Cloud Organization Policies](https://cloud.google.com/resource-manager/docs/organization-policy/overview)
- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/) 
