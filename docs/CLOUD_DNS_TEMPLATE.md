# Cloud DNS Template

The Cloud DNS template (`_common/templates/cloud_dns.hcl`) deploys Google Cloud DNS zones using the [terraform-google-cloud-dns](https://github.com/terraform-google-modules/terraform-google-cloud-dns) module v6.0.0. It handles public and private zones, DNSSEC, environment-aware defaults via `dns.hcl`, and automatic zone naming from the directory structure.

A companion peering template (`_common/templates/cloud_dns_peering.hcl`) publishes private zones across VPC peering connections.

## Module Source

```
git::https://github.com/terraform-google-modules/terraform-google-cloud-dns.git?ref=v6.0.0
```

Version pinned in `_common/common.hcl` as `module_versions.cloud_dns`.

## Required Inputs

| Parameter | Description | Example |
|-----------|-------------|---------|
| `domain` | Fully qualified domain name (trailing dot) | `"dev.example.io."` |
| `project_id` | GCP project ID (via dependency) | `"perimeter-dns-infra"` |

## Optional Inputs

| Parameter | Default | Description |
|-----------|---------|-------------|
| `type` | `"public"` | Zone type (`public` / `private`) |
| `description` | `"Managed by Terragrunt"` | Zone description |
| `ttl` | `300` | Default TTL for records |
| `enable_dnssec` | `true` | Enable DNSSEC for the zone |
| `dnssec_algorithm` | `"rsasha256"` | DNSSEC signing algorithm |
| `recordsets` | `[]` | DNS records to create |
| `labels` | `{}` | Resource labels |
| `private_visibility_config_networks` | `[]` | VPC self links with access to private zones |

## Directory Structure

Private zones reachable from VPN clients live in the hub project; environment-specific zones sit alongside their owning projects:

```
live/
└── non-production/
    ├── hub/
    │   └── dns-hub/                        # Shared DNS project for VPN-facing zones
    │       ├── project/
    │       └── global/cloud-dns/
    │           ├── dns.hcl
    │           └── dev-example-io-internal/
    │               └── terragrunt.hcl
    └── perimeter/
        └── dns-infra/                      # Environment-specific DNS project
            └── global/cloud-dns/
                ├── dns.hcl
                └── <project>-dev-example-io-internal/
                    └── terragrunt.hcl
```

## Basic Usage

Public zone with common record types:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "dns_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns.hcl"
  merge_strategy = "deep"
}

locals {
  dns_vars = read_terragrunt_config("../dns.hcl")
}

inputs = {
  domain      = "example.com."
  description = "Public DNS zone for example.com"

  recordsets = [
    {
      name    = ""
      type    = "A"
      ttl     = 300
      records = ["192.0.2.1"]
    },
    {
      name    = "www"
      type    = "CNAME"
      ttl     = 300
      records = ["example.com."]
    },
    {
      name    = ""
      type    = "MX"
      ttl     = 300
      records = ["10 mail.example.com.", "20 mail2.example.com."]
    }
  ]
}
```

## Common Patterns

### Private Zone (Hub, VPN-visible)

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

### Peering Zone

Use `_common/templates/cloud_dns_peering.hcl` to expose a producer VPC's private zone to a consumer project (e.g. the `vpn-gateway` project):

```hcl
include "dns_peering_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns_peering.hcl"
  merge_strategy = "deep"
}

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

## Supported Record Types

| Type | Purpose | Example |
|------|---------|---------|
| A | IPv4 address | `["192.0.2.1"]` |
| AAAA | IPv6 address | `["2001:db8::1"]` |
| CNAME | Canonical name | `["target.example.com."]` |
| MX | Mail exchange | `["10 mail.example.com."]` |
| TXT | Text records | `["\"v=spf1 include:_spf.google.com ~all\""]` |
| NS | Name server | `["ns1.example.com."]` |
| SRV | Service | `["10 60 5060 sip.example.com."]` |
| CAA | Certificate authority | `["0 issue \"letsencrypt.org\""]` |

## DNSSEC

DNSSEC is enabled by default. To disable for a specific zone, set `enable_dnssec = false`.

| Algorithm | Key Signing | Zone Signing |
|-----------|------------|--------------|
| rsasha256 | 2048 bits | 1024 bits |
| ecdsap256sha256 | 256 bits | 256 bits |
| ecdsap384sha384 | 384 bits | 384 bits |

## CI/CD Integration

| Setting | Value |
|---------|-------|
| Resource type | `cloud-dns` |
| Dependencies | `projects` |
| Path pattern | `live/**/global/cloud-dns/**` |
| Config file | `.github/workflow-config/resource-definitions.yml` |

## Best Practices

- Always use FQDNs with trailing dot (e.g. `example.com.` not `example.com`).
- Use shorter TTLs (300-600) during migrations; longer TTLs (3600+) for stable production records.
- Enable DNSSEC for all public zones.
- Deploy DNS zones in a dedicated perimeter project for security isolation.
- Use CNAME records for flexibility and implement SPF/DKIM/DMARC for email domains.

## Troubleshooting

| Error | Cause | Resolution |
|-------|-------|------------|
| `Error 409: ManagedZone already exists` | Zone exists in GCP but not in state | `terragrunt import google_dns_managed_zone.dns_zone projects/PROJECT_ID/managedZones/ZONE_NAME` |
| `CNAME and other records cannot coexist` | Record type conflict | Remove conflicting A/AAAA records before adding CNAME |
| Private zone not resolving | VPC not authorized | Verify VPC is in `private_visibility_config_networks` and VM uses 169.254.169.254 |

```bash
# List DNS zones
gcloud dns managed-zones list --project=perimeter-dns-infra

# Test DNS resolution (from VPN client)
dig @10.11.2.10 development.dev.example.io
```

## References

- [Google Cloud DNS documentation](https://cloud.google.com/dns/docs)
- [terraform-google-cloud-dns module](https://github.com/terraform-google-modules/terraform-google-cloud-dns)
- [Configuration Templates Overview](CONFIGURATION_TEMPLATES.md)
