# Org-level IAM bindings for non-production account

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "org_iam_template" {
  path           = "${get_repo_root()}/_common/templates/org_iam_bindings.hcl"
  merge_strategy = "deep"
}

locals {
  org_id             = include.base.locals.merged.org_id
  org_service_member = "serviceAccount:${include.base.locals.merged.org_service_account}" # set in account.hcl

  # ============================================================================
  # 1. USER ROLES (User -> [roles])
  # ============================================================================

  user_roles = {
    "user:admin@example.com" = [
      "roles/compute.admin",
      "roles/compute.networkAdmin",
      "roles/iam.securityAdmin",
      "roles/owner",
      "roles/resourcemanager.organizationAdmin",
      "roles/resourcemanager.projectDeleter",
      "roles/secretmanager.secretAccessor",
    ]
  }

  # ============================================================================
  # 2. GROUP ROLES (Group -> [roles])
  # ============================================================================

  group_roles = {
    # DevOps team
    "group:gg_org-devops@example.com" = [
      "roles/editor",
      "roles/resourcemanager.folderViewer",
    ]

    # Operations team
    "group:gg_org-operations@example.com" = [
      "roles/viewer",
      "roles/logging.viewer",
      "roles/monitoring.viewer",
    ]

    # Security team
    "group:gg_org-security@example.com" = [
      "roles/iam.securityReviewer",
      "roles/resourcemanager.organizationViewer",
    ]

    # Billing admins
    "group:gg_org-billing-admins@example.com" = [
      "roles/billing.admin",
      "roles/billing.creator",
      "roles/resourcemanager.organizationViewer",
    ]

    # Organization admins
    "group:gg_org-organization-admins@example.com" = [
      "roles/billing.user",
      "roles/cloudkms.admin",
      "roles/cloudsupport.admin",
      "roles/iam.organizationRoleAdmin",
      "roles/orgpolicy.policyAdmin",
      "roles/pubsub.admin",
      "roles/resourcemanager.organizationAdmin",
      "roles/resourcemanager.projectCreator",
      "roles/securitycenter.admin",
    ]

    # Security admins
    "group:gg_org-security-admins@example.com" = [
      "roles/cloudkms.admin",
      "roles/compute.viewer",
      "roles/container.viewer",
      "roles/iam.organizationRoleViewer",
      "roles/iam.securityAdmin",
      "roles/iam.securityReviewer",
      "roles/iam.serviceAccountCreator",
      "roles/logging.admin",
      "roles/logging.configWriter",
      "roles/logging.privateLogViewer",
      "roles/monitoring.admin",
      "roles/orgpolicy.policyAdmin",
      "roles/securitycenter.admin",
    ]

    # VPC network admins
    "group:gg_org-vpc-network-admins@example.com" = [
      "roles/compute.networkAdmin",
      "roles/compute.securityAdmin",
      "roles/compute.xpnAdmin",
    ]
  }

  # ============================================================================
  # 3. SERVICE ACCOUNT BINDINGS (static only)
  # ============================================================================

  # Terraform automation service account
  tofu_sa_org_bindings = {
    "roles/billing.user"                      = [local.org_service_member]
    "roles/essentialcontacts.admin"           = [local.org_service_member]
    "roles/resourcemanager.folderAdmin"       = [local.org_service_member]
    "roles/resourcemanager.organizationAdmin" = [local.org_service_member]
    "roles/resourcemanager.projectCreator"    = [local.org_service_member]
    "roles/resourcemanager.projectDeleter"    = [local.org_service_member]
    "roles/resourcemanager.projectIamAdmin"   = [local.org_service_member]
    "roles/secretmanager.admin"               = [local.org_service_member]
    "roles/securitycenter.adminEditor"        = [local.org_service_member]
  }

  # ============================================================================
  # 4. TRANSFORMS
  # ============================================================================

  # Transform user_roles to user_bindings (Role -> [users])
  user_bindings = {
    for role in distinct(flatten(values(local.user_roles))) :
    role => sort(distinct([
      for user, roles in local.user_roles : user if contains(roles, role)
    ]))
  }

  # Transform group_roles to group_bindings (Role -> [groups])
  group_bindings = {
    for role in distinct(flatten(values(local.group_roles))) :
    role => sort(distinct([
      for group, roles in local.group_roles : group if contains(roles, role)
    ]))
  }

  # ============================================================================
  # 5. MERGE STATIC BINDINGS
  # ============================================================================

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
}

inputs = {
  organizations = [local.org_id]
  mode          = "authoritative"

  bindings = local.static_bindings
}
