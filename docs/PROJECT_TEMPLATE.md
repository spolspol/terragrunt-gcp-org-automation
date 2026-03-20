# Project Template

The Project template (`_common/templates/project.hcl`) creates GCP projects using the [terraform-google-project-factory](https://github.com/terraform-google-modules/terraform-google-project-factory) module (v18.0.0). Projects are the second resource in the dependency chain, created inside folders and hosting all subsequent infrastructure.

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `name` | Project name | `"dp-dev-01"` |
| `org_id` | Organisation ID | `"123456789"` |
| `billing_account` | Billing account ID | `"ABCDEF-123456-789012"` |
| `folder_id` | Parent folder ID | `"folders/123456789"` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `auto_create_network` | `false` | Create default VPC network |
| `activate_apis` | See template | APIs to enable |
| `budget_amount` | Environment-specific | Monthly budget limit |
| `budget_alert_emails` | `[]` | Email addresses for budget alerts |
| `usage_bucket_name` | `null` | Centralised billing usage reports bucket |
| `usage_bucket_prefix` | Project name | Prefix for usage data in bucket |
| `labels` | See template | Project labels |

## Directory Structure

```
live/non-production/development/
├── platform/
│   └── dp-dev-01/
│       └── project/               # Data platform project
│           └── terragrunt.hcl
└── functions/
    └── fn-dev-01/
        └── project/               # Cloud Run project
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

include "project_template" {
  path           = "${get_repo_root()}/_common/templates/project.hcl"
  merge_strategy = "deep"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "folders/123456789"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  skip_outputs = true
}

inputs = {
  name            = "${include.base.locals.merged.name_prefix}-${include.base.locals.merged.project_id}"
  org_id          = include.base.locals.merged.org_id
  billing_account = include.base.locals.merged.billing_account
  folder_id       = try(dependency.folder.outputs.folder_id, "folders/mock-folder-id")

  budget_amount = include.base.locals.merged.environment_type == "production" ? 1000 : 100

  budget_alert_emails = [
    "finance@example.com",
    "devops@example.com"
  ]

  labels = merge(
    {
      component   = "project"
      environment = include.base.locals.environment
    },
    include.base.locals.standard_labels
  )
}
```

### Billing Usage Reports

Projects can export usage data to a centralised bucket for cost analysis:

```hcl
inputs = {
  usage_bucket_name   = "org-billing-usage-reports"
  usage_bucket_prefix = "my-project"
}
```

## Deployment Order

1. **Folders** -- create organisational folders
2. **Projects** -- create projects within folders
3. **Project Resources** -- deploy VPC, IAM, and workloads

## Best Practices

- Set budget alerts for every project to avoid cost surprises
- Enable only the APIs each project actually needs
- Use centralised billing buckets for organisation-wide cost analysis
- Create dedicated service accounts for automation
- Label comprehensively for billing and governance

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Billing access error | Ensure `roles/billing.user` on the service account |
| Folder permission error | Check `roles/resourcemanager.projectCreator` on the folder |
| API enablement failure | Verify the API exists in the region and check org policy restrictions |

```bash
gcloud projects list --filter="parent.id=FOLDER_ID"
gcloud services list --enabled --project=PROJECT_ID
gcloud beta billing projects describe PROJECT_ID
```

## Module Outputs

| Output | Description |
|--------|-------------|
| `project_id` | ID of the created project |
| `project_name` | Name of the project |
| `project_number` | Numeric project identifier |
| `service_account_email` | Project service account email |

## References

- [terraform-google-project-factory](https://github.com/terraform-google-modules/terraform-google-project-factory)
- [Google Cloud Project documentation](https://cloud.google.com/resource-manager/docs/creating-managing-projects)
- [Project Factory Best Practices](https://cloud.google.com/docs/enterprise/best-practices-for-enterprise-organizations)
