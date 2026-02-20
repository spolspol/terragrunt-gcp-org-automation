locals {
  project_name = "vpn-gateway"
  project_id   = "org-vpn-gateway"

  # Project-specific labels
  project_labels = {
    project     = "vpn-gateway"
    project_id  = "org-vpn-gateway"
    cost_center = "infrastructure"
    purpose     = "vpn-gateway"
  }
}
