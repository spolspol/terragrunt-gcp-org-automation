# Central Firewall Configuration
# This file contains shared configuration for all firewall rules in this directory

locals {
  # Allowed IP ranges for all firewall rules
  allowed_ip_ranges = [
    "10.0.0.0/24",      # Example Office Network
    "192.168.1.0/24",   # Example VPN Range
    "172.16.0.0/16",    # Example Private Network
    "203.0.113.0/24"    # Example Public IP Range (documentation range)
  ]

  # Common firewall rule defaults
  common_firewall_config = {
    direction               = "INGRESS"
    priority                = 1000
    ranges                  = local.allowed_ip_ranges
    source_tags             = null
    source_service_accounts = null
    target_service_accounts = null
    deny                    = []
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
    disabled = false
  }
}
