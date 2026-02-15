# Centralised Hierarchy Reader
# Include this file with `expose = true` in resource terragrunt.hcl files
# to eliminate the repeated locals block that reads and merges hierarchy configs.
#
# Usage:
#   include "base" {
#     path   = "${get_repo_root()}/_common/base.hcl"
#     expose = true
#   }
#
# Then reference values via: include.base.locals.<key>
#   e.g. include.base.locals.merged.project_name
#        include.base.locals.standard_labels
#        include.base.locals.region

locals {
  repo_root = get_repo_root()

  # ── Required hierarchy configs ──────────────────────────────────────────────
  # find_in_parent_folders resolves from the CHILD's directory when used in an
  # included config, so these will correctly walk up from the resource dir.
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  common_vars  = read_terragrunt_config("${local.repo_root}/_common/common.hcl")

  # ── Semi-optional hierarchy configs ────────────────────────────────────────
  # env.hcl exists for most resources but NOT for org-level configs
  # (org-iam-bindings sits directly under the account level).
  _env_locals = try(read_terragrunt_config(find_in_parent_folders("env.hcl")).locals, {})
  # project.hcl exists for most resources but NOT for folder-level configs
  # (folders sit above the project level in the hierarchy).
  _project_locals = try(read_terragrunt_config(find_in_parent_folders("project.hcl")).locals, {})

  # ── Optional hierarchy configs — silently skipped when absent ───────────────
  # Wrap entire read chain in try() to avoid HCL conditional type-mismatch
  # errors (read_terragrunt_config returns a complex object that can't match
  # a simple map literal in a ternary).
  _region_locals = try(read_terragrunt_config(find_in_parent_folders("region.hcl")).locals, {})

  # ── Single merged map ───────────────────────────────────────────────────────
  # Replaces the per-file merge() calls. Later entries override earlier ones.
  # Domain-specific configs (secrets.hcl, compute.hcl) are loaded directly by
  # resources that need them via their own include blocks with expose = true.
  merged = merge(
    local.account_vars.locals,
    local._env_locals,
    local._project_locals,
    local._region_locals,
    local.common_vars.locals
  )

  # ── Common derived values ───────────────────────────────────────────────────
  name_prefix      = try(local.merged.name_prefix, "")
  resource_name    = basename(get_terragrunt_dir())
  region           = try(local.merged.region, "europe-west2")
  environment      = try(local.merged.environment, "")
  environment_type = try(local.merged.environment_type, "")
  module_versions  = local.merged.module_versions
  project_name     = try(local.merged.project_name, "")

  # ── Standard labels ─────────────────────────────────────────────────────────
  # Ready to merge with resource-specific labels in each resource file.
  standard_labels = merge(
    {
      environment      = local.environment
      environment_type = local.environment_type
      managed_by       = "terragrunt"
    },
    try(local.merged.org_labels, {}),
    try(local.merged.env_labels, {}),
    try(local.merged.project_labels, {})
  )
}
