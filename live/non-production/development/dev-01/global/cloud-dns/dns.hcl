# Default DNS configuration for all zones in this project
# Individual zones inherit these settings and can override them

locals {
  # Default TTL for DNS records
  default_ttl = 300

  # Default zone settings
  default_zone_config = {
    type       = "private"
    visibility = "private"
  }

  # DNSSEC configuration (disabled for private zones)
  dnssec_config = {
    state = "off"
  }

  # Common labels for all DNS zones
  common_dns_labels = {
    managed_by   = "terragrunt"
    dns_provider = "cloud-dns"
    project_type = "development"
    visibility   = "private"
  }
}
