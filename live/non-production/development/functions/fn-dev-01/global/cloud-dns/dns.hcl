# Default DNS configuration for fn-dev-01 zones

locals {
  default_ttl = 300

  default_zone_config = {
    type       = "private"
    visibility = "private"
  }

  dnssec_config = {
    state = "off"
  }

  common_dns_labels = {
    managed_by   = "terragrunt"
    dns_provider = "cloud-dns"
    project_type = "functions"
    visibility   = "private"
  }
}
