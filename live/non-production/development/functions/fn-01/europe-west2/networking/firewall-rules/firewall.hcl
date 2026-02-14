# Central firewall configuration for fn-01

locals {
  allowed_ip_ranges = [
    "10.20.0.0/16",   # fn-01 VPC address space
    "10.11.100.0/24",  # VPN default client pool
    "10.11.101.0/24"   # VPN admin client pool
  ]

  vpn_server_ranges = ["10.11.2.0/24"]
  admin_vpn_ranges  = concat(local.vpn_server_ranges, ["10.11.101.0/24"])

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

  nat_config = {
    nat_tags          = ["nat-enabled", "serverless-subnet"]
    nat_egress_ranges = ["0.0.0.0/0"]
    nat_egress_ports = {
      tcp = ["80", "443", "53"]
      udp = ["53", "123"]
    }
  }

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
