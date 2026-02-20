# Workload Identity Template
# Creates GSA + WI binding for GKE workloads
# Uses terraform-google-kubernetes-engine workload-identity submodule
#
# This module creates:
# - GSA (Google Service Account)
# - IAM binding (roles/iam.workloadIdentityUser) for KSA -> GSA impersonation
#
# This module does NOT create:
# - KSA (Kubernetes Service Account) - created by Helm charts via ArgoCD
#
# NOTE: Project-level IAM roles should be assigned via iam-bindings, not this module
#
# Naming convention: {cluster-id}-{workload-name}
# Examples: cluster-01-argocd-server, cluster-02-external-dns

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git//modules/workload-identity?ref=${local.module_versions.gke}"
}

locals {
  common_vars     = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  module_versions = local.common_vars.locals.module_versions
}

inputs = {
  # Do NOT create KSA - Helm charts handle KSA creation
  use_existing_k8s_sa             = true
  annotate_k8s_sa                 = false
  automount_service_account_token = false

  # Do NOT assign project roles here - use iam-bindings instead
  roles = []
}
