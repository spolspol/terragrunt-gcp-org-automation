# Organisation IAM Bindings Template

## Overview

The `org_iam_bindings.hcl` template manages organisation-level IAM bindings using the [terraform-google-iam](https://github.com/terraform-google-modules/terraform-google-iam) module's `organizations_iam` submodule.

## Module

- **Source**: `terraform-google-modules/iam/google//modules/organizations_iam`
- **Version**: Defined in `_common/common.hcl` under `module_versions.iam`

## Usage Pattern

Organisation IAM bindings are defined in `live/<account>/org-iam-bindings/terragrunt.hcl` using a structured approach:

### 1. User Roles (User -> [roles])

Map individual users to their required roles:

```hcl
user_roles = {
  "user:admin@example.com" = [
    "roles/owner",
    "roles/resourcemanager.organizationAdmin",
  ]
}
```

### 2. Group Roles (Group -> [roles])

Map Google Groups to their required roles:

```hcl
group_roles = {
  "group:gg_org-devops@example.com" = [
    "roles/editor",
    "roles/resourcemanager.folderViewer",
  ]
  "group:gg_org-security@example.com" = [
    "roles/iam.securityReviewer",
    "roles/resourcemanager.organizationViewer",
  ]
}
```

### 3. Service Account Bindings

Map roles to service accounts (role -> [members] format):

```hcl
tofu_sa_org_bindings = {
  "roles/resourcemanager.organizationAdmin" = [local.org_service_member]
  "roles/resourcemanager.projectCreator"    = [local.org_service_member]
}
```

### 4. Transforms

The template automatically transforms user/group-centric definitions into role-centric bindings:

```hcl
# User -> [roles] becomes Role -> [users]
user_bindings = {
  for role in distinct(flatten(values(local.user_roles))) :
  role => sort(distinct([
    for user, roles in local.user_roles : user if contains(roles, role)
  ]))
}
```

### 5. Merge

All binding sources are merged into a single `static_bindings` map:

```hcl
static_bindings = {
  for role in distinct(concat(
    keys(local.tofu_sa_org_bindings),
    keys(local.user_bindings),
    keys(local.group_bindings),
  )) :
  role => distinct(concat(
    lookup(local.tofu_sa_org_bindings, role, []),
    lookup(local.user_bindings, role, []),
    lookup(local.group_bindings, role, []),
  ))
}
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `organizations` | List of organisation IDs | Required |
| `mode` | Binding mode (`authoritative` or `additive`) | `authoritative` |
| `bindings` | Map of role -> [members] | Required |

## Security Considerations

- Organisation-level bindings affect **all resources** under the organisation
- Use `authoritative` mode with caution - it removes any bindings not in the configuration
- Always include the automation service account to prevent lockout
- Changes require review from the security team (enforced via CODEOWNERS)

## Related Templates

- [Folder IAM Bindings](./IAM_BINDINGS_TEMPLATE.md) - Folder-level IAM
- [Project IAM Bindings](./IAM_BINDINGS_TEMPLATE.md) - Project-level IAM
