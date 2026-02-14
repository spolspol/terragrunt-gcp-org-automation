# Common networking configuration for VPN gateway
# Defines reserved internal IPs and common networking settings

locals {
  # Reserved internal IP addresses
  reserved_internal_ips = {
    vpn-server = {
      address         = "10.11.2.10"
      subnetwork_index = 1
      description     = "Reserved internal IP for VPN server"
    }
  }
}
