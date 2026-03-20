# Cloud DNS Private Zones

Private Cloud DNS zones provide internal name resolution within VPC networks for Private Service Connect endpoints, GKE cluster services, Cloud SQL private IPs, and internal load balancers.

**Module version**: `cloud_dns = "v6.0.0"` (pinned in `_common/common.hcl`)

**Templates**: `_common/templates/cloud_dns.hcl`, `_common/templates/cloud_dns_peering.hcl`

## Architecture

### Naming Convention

Private zones follow the pattern `{project}.{env}.example.io`:

| Environment | Zone | Purpose |
|-------------|------|---------|
| Development | `dp-dev-01.dev.example.io.` | Project-scoped DNS |
| Development | `dev.example.io.` | Hub zone for VPN clients |
| UAT | `dp-dev-01.uat.example.io.` | Data Platform UAT |
| UAT | `fn-dev-01.uat.example.io.` | Functions UAT |

### Directory Layout

```
live/non-production/
  development/
    functions/fn-dev-01/global/cloud-dns/     # fn-dev-01 private zones
    dp-dev-01/global/cloud-dns/               # dp-dev-01 private zones
  hub/
    dns-hub/global/cloud-dns/                 # Shared hub zones (VPN-wide)
    vpn-gateway/global/cloud-dns/peering/     # Peering zones for VPN access
```

## Implementation

### 1. Private DNS Zone

Each project creates a private zone associated with its VPC network.

**Shared defaults** (`dns.hcl`):

```hcl
locals {
  default_ttl      = 300
  enable_dnssec    = false
  type             = "private"
  visibility       = "private"
  dns_labels = {
    managed_by   = "terragrunt"
    dns_provider = "google-cloud-dns"
    visibility   = "private"
  }
}
```

**Zone implementation** (`terragrunt.hcl`):

```hcl
include "dns_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns.hcl"
  merge_strategy = "deep"
}

dependency "network" {
  config_path = "../../../vpc-network"
}

inputs = {
  domain      = "dp-dev-01.dev.example.io."
  description = "Private DNS zone for dp-dev-01 internal resources"
  type        = "private"
  visibility  = "private"

  private_visibility_config_networks = [
    dependency.network.outputs.network_self_link
  ]

  recordsets = [
    {
      name    = "postgres-main"
      type    = "A"
      ttl     = 300
      records = ["10.199.16.3"]
    }
  ]
}
```

### 2. Shared Hub Zone (`dev.example.io.`)

The `dns-hub` project hosts a zone attached directly to the VPN Gateway VPC for records reachable by all VPN clients.

```hcl
dependency "vpn_gateway_network" {
  config_path = "${get_repo_root()}/live/non-production/hub/vpn-gateway/vpc-network"
}

inputs = {
  domain     = "dev.example.io."
  type       = "private"
  visibility = "private"

  private_visibility_config_networks = [
    dependency.vpn_gateway_network.outputs.network_self_link
  ]

  recordsets = [
    {
      name    = "development"
      type    = "CNAME"
      ttl     = 300
      records = ["cluster-01.ew2.dp-dev-01.dev.example.io."]
    }
  ]
}
```

Application ingress follows `https://<app>.dp-dev-01.dev.example.io`. No peering zone is needed since this zone is directly associated with the VPN Gateway VPC.

### 3. GKE Cloud DNS Integration

GKE clusters can use Cloud DNS as their DNS provider instead of kube-dns:

```hcl
inputs = {
  cluster_dns_provider = "CLOUD_DNS"
  cluster_dns_scope    = "VPC_SCOPE"   # Extends DNS to entire VPC
  dns_cache            = true          # NodeLocal DNSCache

  stub_domains = {
    "dp-dev-01.dev.example.io" = ["169.254.169.254"]
  }
}
```

**DNS scope options**:
- **CLUSTER_SCOPE** (default): DNS records only resolvable within the cluster
- **VPC_SCOPE** (recommended): Extends to entire VPC; required for PSC integration

### 4. DNS Peering to VPN Gateway

Peering zones in `vpn-gateway` forward queries for `{project}.dev.example.io` into each producer VPC without duplicating records. Each zone uses `_common/templates/cloud_dns_peering.hcl`:

```hcl
dependency "target_network" {
  config_path = "${get_repo_root()}/live/non-production/development/dp-dev-01/vpc-network"
}

inputs = {
  domain      = "dp-dev-01.dev.example.io."
  description = "Peering zone exposing dp-dev-01 private DNS to VPN clients"
  peering_config = [
    {
      target_network = {
        network_url = dependency.target_network.outputs.network_self_link
      }
    }
  ]
}
```

### 5. DNS Forwarding for VPN Clients

The VPN server runs `dnsmasq` to forward `*.dev.example.io` queries to Google's metadata resolver (`169.254.169.254`), which honours Cloud DNS peering. Key settings from `vpn_dns_settings` in the VPN gateway compute config:

- **Bind address**: `10.11.2.10` (metadata key `dns-bind-address`)
- **Forward domain**: `dev.example.io` (metadata key `dns-forward-domain`)
- **Firewall**: `allow-vpn-dns` permits TCP/UDP 53 from VPN pools to the VPN server

## Private Service Connect

PSC endpoints require manual DNS records since they are not created automatically:

1. Create the PSC endpoint with a reserved IP
2. Add an A record in the project's private zone pointing to that IP
3. Use the DNS name in connection strings (e.g. `postgres-main.dp-dev-01.dev.example.io`)

## Managing Records

### Via Terragrunt (preferred)

Add entries to the `recordsets` array in the zone's `terragrunt.hcl`, then apply:

```bash
cd live/non-production/development/dp-dev-01/global/cloud-dns/dp-dev-01-dev-example-io-internal
terragrunt apply --auto-approve
```

### Via gcloud (ad-hoc)

```bash
gcloud dns record-sets create <name>.dp-dev-01.dev.example.io. \
  --zone=dp-dev-01-dev-example-io-internal \
  --type=A --ttl=300 --rrdatas=<IP_ADDRESS> \
  --project=dp-dev-01-a
```

## Testing

```bash
# From GKE cluster
kubectl run dns-test --image=busybox --rm -it --restart=Never -- \
  nslookup cluster-01.ew2.dp-dev-01.dev.example.io

# Verify zone configuration
gcloud dns managed-zones describe dp-dev-01-dev-example-io-internal \
  --project=dp-dev-01-a

# List all records
gcloud dns record-sets list \
  --zone=dp-dev-01-dev-example-io-internal \
  --project=dp-dev-01-a
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Pods cannot resolve private zone records | Verify `cluster_dns_scope = "VPC_SCOPE"` and zone is associated with the VPC |
| PSC endpoint not resolving | Confirm DNS A record exists and PSC endpoint is in ACCEPTED state |
| Cluster still using kube-dns | Verify `cluster_dns_provider = "CLOUD_DNS"` is set; check cluster events |

**Debug**: `kubectl get pods -n kube-system | grep dns` -- Cloud DNS shows `cloud-dns-*` pods; kube-dns shows `kube-dns-*`.

## Best Practices

1. **Naming**: Use `{service}-{type}` pattern (e.g. `postgres-main`, `redis-cache`)
2. **TTL**: 300s for dynamic services, 3600s for stable services
3. **Security**: Keep zones private; use separate zones per environment
4. **Peering**: Use DNS peering zones rather than duplicating records across VPCs
5. **Documentation**: Maintain a record of all PSC endpoint DNS mappings

## References

- [Cloud DNS for GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/cloud-dns)
- [Cloud DNS Private Zones](https://cloud.google.com/dns/docs/zones)
- [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect)
- [Terraform Google DNS Module](https://registry.terraform.io/modules/terraform-google-modules/cloud-dns/google/latest)
