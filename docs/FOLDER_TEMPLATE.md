# Folder Template

The Folder template (`_common/templates/folder.hcl`) creates GCP organisational folders using the [terraform-google-folders](https://github.com/terraform-google-modules/terraform-google-folders) module (v5.0.0). Folders are the first resource in the dependency chain -- every environment and project sits beneath one.

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `folder_name` | Name of the folder to create | `"dev-environment"` |
| `parent` | Parent resource (organisation or folder) | `"organizations/123456789"` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `folder_iam_members` | `{}` | IAM members to assign |
| `folder_iam_roles` | `[]` | IAM roles to bind |
| `org_policies` | `{}` | Organisation policies to apply |
| `folder_labels` | See template | Resource labels |

## Directory Structure

```
live/non-production/
├── development/
│   └── folder/                    # Development environment folder
│       └── terragrunt.hcl
├── hub/
│   └── folder/                    # Hub environment folder
│       └── terragrunt.hcl
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
    { component = "folder" }
  )
}
```

### Hierarchical Folder Structure

```hcl
inputs = {
  folder_name = "${include.base.locals.merged.name_prefix}-${include.base.locals.environment}-workloads"
  parent      = "folders/123456789"  # Parent folder ID

  org_policies = {
    "constraints/compute.restrictLoadBalancerCreationForTypes" = {
      allow_all     = false
      denied_values = ["EXTERNAL"]
    }
  }
}
```

## Deployment Order

1. **Organisation Setup** -- configure org-level settings
2. **Root Folders** -- create top-level folders (hub, development, production)
3. **Sub-folders** -- create pattern-specific folders (functions, platform)
4. **Projects** -- create projects within folders

## Best Practices

- Use folders to enforce logical separation between environments and teams
- Apply organisation policies at folder level for inherited security constraints
- Grant minimal IAM permissions (least privilege)
- Use standardised naming with the organisation prefix
- Label folders for cost allocation and governance

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Permission errors | Ensure the service account has `roles/resourcemanager.folderCreator` |
| Parent not found | Verify the parent organisation or folder ID exists |
| Policy violations | Check for conflicting organisation policies |

```bash
gcloud resource-manager folders list --organization=ORGANIZATION_ID
gcloud resource-manager folders describe FOLDER_ID
gcloud resource-manager folders get-iam-policy FOLDER_ID
```

## Module Outputs

| Output | Description |
|--------|-------------|
| `folder_id` | ID of the created folder (`"folders/123456789"`) |
| `folder_name` | Display name of the folder |
| `folder_parent` | Parent resource of the folder |

## References

- [terraform-google-folders module](https://github.com/terraform-google-modules/terraform-google-folders)
- [Google Cloud Resource Manager](https://cloud.google.com/resource-manager/docs)
- [Organisation Policies](https://cloud.google.com/resource-manager/docs/organization-policy/overview)
