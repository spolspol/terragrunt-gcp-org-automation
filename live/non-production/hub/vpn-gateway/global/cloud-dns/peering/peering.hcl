locals {
  description = "DNS peering zone exposing project-private DNS to VPN clients"

  labels = {
    managed_by   = "terragrunt"
    dns_provider = "google-cloud-dns"
    project_type = "vpn-gateway"
    zone_type    = "peering"
  }
}
