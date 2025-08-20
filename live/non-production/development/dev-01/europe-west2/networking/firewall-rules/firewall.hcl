# Central Firewall Configuration
# This file contains shared configuration for all firewall rules in this directory

locals {
  # Allowed IP ranges for all firewall rules
  allowed_ip_ranges = [
    "10.0.0.0/24",      # Office network
    "192.168.1.0/24",   # VPN range
    "172.16.0.0/16",    # Private network
    "203.0.113.0/24"    # Public range (documentation example)
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

  # NAT Gateway related configuration
  nat_config = {
    # Common NAT network tags
    nat_tags = ["nat-enabled", "gke-node", "public-subnet"]

    # Common egress destinations for NAT traffic
    nat_egress_ranges = ["0.0.0.0/0"]

    # Common NAT egress ports
    nat_egress_ports = {
      tcp = ["80", "443", "53", "6443"]
      udp = ["53", "123"]
    }
  }

  # Common egress firewall rule defaults for NAT
  common_egress_config = {
    direction               = "EGRESS"
    priority                = 1000
    ranges                  = local.nat_config.nat_egress_ranges
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