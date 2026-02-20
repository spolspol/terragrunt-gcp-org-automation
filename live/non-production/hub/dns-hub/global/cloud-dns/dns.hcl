locals {
  # Default configuration for all DNS zones in this project
  default_ttl = 300

  # Common labels for all zones
  dns_labels = {
    managed_by   = "terragrunt"
    dns_provider = "google-cloud-dns"
    project_type = "dns-infrastructure"
  }

  # Default DNSSEC settings
  enable_dnssec    = true
  dnssec_algorithm = "rsasha256"
}
