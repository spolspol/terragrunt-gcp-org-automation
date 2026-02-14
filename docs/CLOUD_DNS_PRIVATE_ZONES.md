<!-- Space: PE -->
<!-- Title: Cloud DNS Private Zones -->
<!-- Parent: Networking Resources -->
<!-- Label: cloud-dns -->
<!-- Label: private-dns -->
<!-- Label: networking -->
<!-- Label: psc -->
<!-- Label: architecture -->

# Cloud DNS Private Zones Documentation

## Overview

This document describes the implementation and configuration of Cloud DNS private zones in the GCP infrastructure, including integration with GKE clusters for Private Service Connect (PSC) support and internal service discovery.

## Architecture

### Private DNS Zone Structure

The organization uses private Cloud DNS zones for internal name resolution within VPC networks. These zones provide DNS resolution for:
- Private Service Connect endpoints
- Internal service discovery
- GKE cluster services
- Cloud SQL private IPs
- Internal load balancers

### Naming Convention

Private zones follow the pattern: `{project}.{env}.example.io`

**Development Environment:**
- `dev-01.dev.example.io.` (Development)
- `dev.example.io.` (Shared hub zone for VPN clients)

**UAT Environment:**
- `dp-01.uat.example.io.` (Data Platform UAT)
- `fn-01.uat.example.io.` (Functions UAT)
- `uat.example.io.` (Shared UAT hub zone for VPN clients)

**Production Environment (future):**
- `prod-01.prod.example.io.` (Production)

## Implementation

### 1. Private DNS Zone Configuration

#### Location
```
# Development Environment
live/non-production/development/dev-01/global/cloud-dns/
├── dns.hcl                         # DNS configuration
└── dev-01-dev-example-io/          # dev-01 private zone implementation
    └── terragrunt.hcl

# UAT Environment
live/non-production/uat/data-platform/dp-01/global/cloud-dns/
├── dns.hcl                         # UAT DNS configuration
└── dp-01-uat-example-io/           # dp-01 private zone
    └── terragrunt.hcl

live/non-production/uat/functions/fn-01/global/cloud-dns/
├── dns.hcl                         # UAT DNS configuration
└── fn-01-uat-example-io/           # fn-01 private zone
    └── terragrunt.hcl

# Hub Zones (DNS Hub project)
live/non-production/hub/dns-hub/global/cloud-dns/
├── dns.hcl                         # Shared hub defaults
├── dev-example-io/                 # Dev VPN-wide private zone
│   └── terragrunt.hcl
└── uat-example-io/                 # UAT VPN-wide private zone
    └── terragrunt.hcl
```

#### Configuration (dns.hcl)
```hcl
locals {
  # Default configuration for all DNS zones in this project
  default_ttl = 300

  # Common labels for all zones
  dns_labels = {
    managed_by   = "terragrunt"
    dns_provider = "google-cloud-dns"
    project_type = "development"
    visibility   = "private"
  }

  # Private zone settings (no DNSSEC for private zones)
  enable_dnssec    = false
  dnssec_algorithm = ""

  # Zone type configuration
  type       = "private"
  visibility = "private"
}
```

#### Dev-01 Zone Implementation (terragrunt.hcl)
```hcl
include "dns_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns.hcl"
  merge_strategy = "deep"
}

dependency "network" {
  config_path = "../../../vpc-network"
}

inputs = {
  # Zone configuration
  domain      = "dev-01.dev.example.io."
  description = "Private DNS zone for dev-01 internal resources and Private Service Connect"

  # Private zone configuration
  type       = "private"
  visibility = "private"

  # Associate with VPC network
  private_visibility_config_networks = [
    dependency.network.outputs.network_self_link
  ]

  # DNS Records for dev-01 internal services (examples)
  recordsets = [
    {
      name    = "postgres-main"
      type    = "A"
      ttl     = 300
      records = ["10.199.16.3"]   # dev-01 Cloud SQL private IP
    },
    {
      name    = "windows-qat-ers"
      type    = "A"
      ttl     = 300
      records = ["10.132.0.21"]   # dev-01 QA Windows host (perimeter subnet)
    }
  ]
}
```

### 2. Shared Hub Zone (`dev.example.io.`)

The `dns-hub` project hosts a single private zone that is attached directly to the VPN Gateway VPC. Use this zone for records that must be reachable by any VPN client, regardless of the environment they connect to.

```hcl
# live/non-production/hub/dns-hub/global/cloud-dns/dev-example-io-internal/terragrunt.hcl

dependency "vpn_gateway_network" {
  config_path = "${get_repo_root()}/live/non-production/hub/vpn-gateway/vpc-network"
}

inputs = {
  domain      = "dev.example.io."
  type        = "private"
  visibility  = "private"

  private_visibility_config_networks = [
    dependency.vpn_gateway_network.outputs.network_self_link
  ]

  recordsets = [
    {
      name    = "development"
      type    = "CNAME"
      ttl     = 300
      records = ["cluster-01.ew2.dev-01.dev.example.io."]
    }
  ]
}
```

- **Purpose**: surface shared aliases and service endpoints to all VPN users.
- **Example**: the `development.dev.example.io` CNAME now resolves to the dev-01 GKE services endpoint.
- **App URLs**: application ingress follows `https://<app>.dev-01.dev.example.io` (e.g., `https://grafana.dev-01.dev.example.io`).
- **Peering**: this zone is directly associated with the VPN Gateway VPC, so no additional Cloud DNS peering is required.

### 3. GKE Integration with Cloud DNS

#### Cloud DNS Provider Configuration

GKE clusters can use Cloud DNS as their DNS provider instead of the default kube-dns, providing:
- Managed DNS service (no cluster-hosted DNS pods)
- Local DNS caching on each node (NodeLocal DNSCache)
- VPC-wide DNS resolution
- Automatic Pod and Service DNS provisioning

#### Cluster Configuration

In `live/non-production/development/dev-01/europe-west2/gke/cluster-02/terragrunt.hcl`:

```hcl
inputs = {
  # ... other configuration ...

  # Cloud DNS provider configuration
  cluster_dns_provider = "CLOUD_DNS"  # Use Cloud DNS instead of kube-dns
  cluster_dns_scope    = "VPC_SCOPE"  # Enable VPC-wide DNS resolution
  dns_cache           = true          # Enable NodeLocal DNSCache

  # Stub domains for internal resolution
  stub_domains = {
  "dev-01.dev.example.io" = ["169.254.169.254"]
  }
}
```

### 4. DNS Peering to vpn-gateway

To make private DNS available to VPN clients, the `vpn-gateway` project hosts Cloud DNS **peering zones** that point at each producer VPC.  These peering zones forward queries for `{project}.dev.example.io` into the originating project without duplicating records.

> The shared `dev.example.io.` zone is attached directly to the VPN gateway VPC and therefore does **not** require a peering zone.

#### Peering Zone Layout
```
live/non-production/hub/vpn-gateway/global/cloud-dns/peering/
├── peering.hcl                              # Shared labels/defaults
├── dev-01/                                  # Peering zone for development VPC
│   └── terragrunt.hcl
├── dp-01/                                   # Peering zone for dp-01 VPC
│   └── terragrunt.hcl
└── fn-01/                                   # Peering zone for fn-01 VPC
    └── terragrunt.hcl
```

Each `terragrunt.hcl` uses the `_common/templates/cloud_dns_peering.hcl` template and depends on the source VPC network to provide the target self link:

```hcl
dependency "target_network" {
  config_path = "${get_repo_root()}/live/non-production/development/dev-01/vpc-network"
}

inputs = {
  domain      = "dev-01.dev.example.io."
  description = "Peering zone exposing dev-01 private DNS to VPN clients"
  peering_config = [
    {
      target_network = {
        network_url = dependency.target_network.outputs.network_self_link
      }
    }
  ]
}
```

This pattern allows every VPC that is peered with `vpn-gateway` to publish its private namespace without sharing records manually.

### 5. DNS Forwarding for VPN Clients

The VPN server now runs `dnsmasq` and advertises a metadata-driven bind address (`dns-bind-address`, default `10.11.2.10`) as the DNS server for all VPN pools.  The service forwards queries for `*.dev.example.io` (metadata key `dns-forward-domain`) to Google's metadata resolver `169.254.169.254`, which in turn honours the Cloud DNS peering configuration. These values are defined via `vpn_dns_settings` in `live/non-production/hub/vpn-gateway/europe-west2/compute/compute.hcl`.

Key updates delivered by the VPN server install script:
```bash
apt-get install -y mongodb-org dnsmasq

cat >/etc/dnsmasq.d/dev-example-io.conf <<EOF
server=/${DNS_FORWARD_DOMAIN}/169.254.169.254
listen-address=127.0.0.1,${DNS_BIND_ADDRESS}
bind-interfaces
EOF
systemctl enable dnsmasq
systemctl restart dnsmasq
```

The VPN server configuration script pushes the new DNS server and search domain to every VPN server:

```python
VPN_DNS_SERVER = "10.11.2.10"
VPN_SEARCH_DOMAIN = "dev.example.io"

update_fields = {
    "dns_servers": [VPN_DNS_SERVER],
    "search_domain": VPN_SEARCH_DOMAIN,
}
```

Firewall rule `allow-vpn-dns` now allows TCP/UDP 53 from all VPN pools to the VPN server instance so that clients can query `dnsmasq`.

#### DNS Scope Options

1. **CLUSTER_SCOPE** (Default)
   - DNS records only resolvable within the cluster
   - Same behavior as kube-dns
   - Isolated to cluster nodes

2. **VPC_SCOPE** (Recommended for PSC)
   - Extends cluster DNS to entire VPC
   - Headless Services resolvable from Compute Engine VMs
   - Enables cross-resource DNS queries
   - Required for Private Service Connect integration

## Private Service Connect Integration

### DNS Requirements for PSC

Private Service Connect requires DNS records for endpoint resolution. Cloud SQL and other PSC-enabled services don't create DNS records automatically.

### Adding PSC Endpoints

When creating a Private Service Connect endpoint:

1. **Create the PSC endpoint**
   ```bash
   gcloud compute addresses create postgres-psc-endpoint \
     --subnet=dev-01-vpc-network-private \
     --address=10.132.8.100 \
     --region=europe-west2 \
     --project=dev-01-a
   ```

2. **Add DNS record**
   ```bash
  gcloud dns record-sets create postgres-main.dev-01.dev.example.io. \
    --zone=dev-01-dev-example-io-internal \
     --type=A \
     --ttl=300 \
     --rrdatas=10.132.8.100 \
     --project=dev-01-a
   ```

3. **Update connection strings**
   ```
  postgresql://user:pass@postgres-main.dev-01.dev.example.io:5432/db  # pragma: allowlist secret
   ```

## DNS Records Management

### Record Types Supported

- **A Records**: IPv4 addresses for services
- **AAAA Records**: IPv6 addresses (if needed)
- **CNAME Records**: Aliases for convenience
- **PTR Records**: Reverse DNS lookups
- **SRV Records**: Service discovery
- **TXT Records**: Metadata and verification

### Adding Records via Terragrunt

Update the `recordsets` array in the zone's terragrunt.hcl:

```hcl
recordsets = [
  {
    name    = "service-name"
    type    = "A"
    ttl     = 300
    records = ["10.132.8.x"]
  }
]
```

Then apply:
```bash
cd live/non-production/development/dev-01/global/cloud-dns/dev-01-dev-example-io-internal
terragrunt apply --auto-approve
```

### Adding Records via gcloud

```bash
# Add A record
gcloud dns record-sets create <name>.dev-01.dev.example.io. \
  --zone=dev-01-dev-example-io-internal \
  --type=A \
  --ttl=300 \
  --rrdatas=<IP_ADDRESS> \
  --project=dev-01-a

# Add CNAME record
gcloud dns record-sets create <alias>.dev-01.dev.example.io. \
  --zone=dev-01-dev-example-io-internal \
  --type=CNAME \
  --ttl=300 \
  --rrdatas=<target>.dev-01.dev.example.io. \
  --project=dev-01-a
```

## Testing and Validation

### From GKE Cluster

```bash
# Get cluster credentials
gcloud container clusters get-credentials dev-01-ew2-cluster-02 \
  --region=europe-west2 \
  --project=dev-01-a

# Test DNS resolution
kubectl run dns-test --image=busybox --rm -it --restart=Never -- \
  nslookup cluster-01.ew2.dev-01.dev.example.io

# Validate custom records you add:
# nslookup <record>.dev-01.dev.example.io
```

### Verify Cloud DNS Configuration

```bash
# Check zone details
gcloud dns managed-zones describe dev-01-dev-example-io-internal \
  --project=dev-01-a

# List all records
gcloud dns record-sets list \
  --zone=dev-01-dev-example-io-internal \
  --project=dev-01-a

# Check cluster DNS configuration
gcloud container clusters describe dev-01-ew2-cluster-02 \
  --region=europe-west2 \
  --project=dev-01-a \
  --format="yaml(clusterDnsConfig)"
```

## Troubleshooting

### Common Issues

#### 1. DNS Resolution Fails from Cluster

**Symptom**: Pods cannot resolve private zone records

**Solutions**:
- Verify cluster has `cluster_dns_scope = "VPC_SCOPE"`
- Check stub domains configuration
- Ensure private zone is associated with the VPC network

#### 2. PSC Endpoint Not Resolving

**Symptom**: Cannot connect to Cloud SQL via DNS name

**Solutions**:
- Verify DNS record exists for the PSC endpoint
- Check PSC endpoint is in ACCEPTED state
- Ensure correct IP address in DNS record

#### 3. Cloud DNS Not Working in GKE

**Symptom**: Cluster still using kube-dns

**Solutions**:
- Check `cluster_dns_provider = "CLOUD_DNS"` is set
- Verify cluster was created/updated with this configuration
- Review cluster events for DNS-related errors

### Debug Commands

```bash
# Check DNS provider in cluster
kubectl get pods -n kube-system | grep dns

# For Cloud DNS, should see:
# cloud-dns-*

# For kube-dns, would see:
# kube-dns-*

# Test from debug pod
kubectl run -it --rm debug --image=gcr.io/google.com/cloudsdktool/cloud-sdk:slim \
  --restart=Never -- bash

# Inside pod:
apt-get update && apt-get install -y dnsutils
nslookup cluster-01.ew2.dev-01.dev.example.io
dig +trace cluster-01.ew2.dev-01.dev.example.io
```

## Best Practices

### 1. Naming Conventions
- Use descriptive names for DNS records
- Follow pattern: `{service}-{type}.{zone}`
- Examples: `postgres-main`, `redis-cache`, `api-internal`

### 2. TTL Settings
- Use 300 seconds (5 minutes) for dynamic services
- Use 3600 seconds (1 hour) for stable services
- Use 86400 seconds (1 day) for static resources

### 3. Security
- Keep zones private (never expose internal IPs)
- Use separate zones per environment
- Implement least-privilege access to DNS management

### 4. Documentation
- Document all DNS records and their purposes
- Keep record of PSC endpoint mappings
- Update when adding new services

## Migration Guide

### Migrating Existing Cluster from kube-dns to Cloud DNS

**Note**: This may require cluster recreation depending on the GKE version.

1. **Check Current Configuration**
   ```bash
   gcloud container clusters describe <cluster-name> \
     --region=<region> \
     --format="value(clusterDnsConfig.clusterDns)"
   ```

2. **Update Terragrunt Configuration**
   ```hcl
   cluster_dns_provider = "CLOUD_DNS"
   cluster_dns_scope    = "VPC_SCOPE"
   dns_cache           = true
   ```

3. **Apply Changes**
   ```bash
   terragrunt plan  # Review if cluster needs recreation
   terragrunt apply --auto-approve
   ```

## Future Enhancements

### Planned Improvements

1. **Multi-Environment DNS**
   - Create zones for staging and production
   - Implement DNS forwarding between environments

2. **DNS Policies**
   - Response policies for split-horizon DNS
   - Geo-based routing for multi-region

3. **Automation**
   - Automatic DNS record creation for PSC endpoints
   - Integration with service mesh for service discovery

4. **Monitoring**
   - DNS query metrics and logging
   - Alert on resolution failures

## References

- [Cloud DNS for GKE Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/cloud-dns)
- [Private Service Connect Overview](https://cloud.google.com/vpc/docs/private-service-connect)
- [Cloud DNS Private Zones](https://cloud.google.com/dns/docs/zones)
- [GKE DNS Configuration](https://cloud.google.com/kubernetes-engine/docs/how-to/cloud-dns#dns_scopes)
- [Terraform Google DNS Module](https://registry.terraform.io/modules/terraform-google-modules/cloud-dns/google/latest)

## Document History

- **2025-09-23**: Initial documentation created
- **2025-09-23**: Added cluster-02 Cloud DNS configuration
- **2025-09-23**: Updated DNS records for cluster-02 ingress endpoints
- **2026-02-06**: Added UAT environment DNS zones (dp-01, fn-01)
- **2026-02-06**: Added uat.example.io hub zone for UAT VPN clients
- **2026-02-06**: Added DNS peering zones for UAT projects
