<!-- Space: PE -->
<!-- Title: Cloud DNS Template -->
<!-- Parent: Networking Resources -->
<!-- Label: cloud-dns -->
<!-- Label: dns -->
<!-- Label: template -->
<!-- Label: networking -->
<!-- Label: intermediate -->

# Cloud DNS Template

This document provides detailed information about the Cloud DNS template available in the Terragrunt GCP infrastructure.

## Overview

The Cloud DNS template (`_common/templates/cloud_dns.hcl`) provides a standardized approach to deploying Google Cloud DNS zones using the [terraform-google-cloud-dns](https://github.com/terraform-google-modules/terraform-google-cloud-dns) module v6.0.0. It ensures consistent DNS zone configuration, DNSSEC security, and environment-aware settings for both public and private DNS zones.

## Features

- Public and private DNS zone management
- DNSSEC support with configurable algorithms
- Comprehensive DNS record types (A, AAAA, CNAME, MX, TXT, SPF, CAA, etc.)
- Global DNS zone deployment in perimeter for security isolation
- Automatic zone naming from directory structure
- Environment-aware configuration through dns.hcl
- Consistent labeling and tagging
- Integration with project dependencies
- Support for zone forwarding and peering
- Dedicated peering template (`_common/templates/cloud_dns_peering.hcl`) for publishing private zones across VPC peering connections

## Module Version

- **Current Version**: v6.0.0
- **Module Source**: terraform-google-cloud-dns
- **Key Changes from v5.2.0**:
  - Removed google-beta provider dependency
  - Requires Terraform/OpenTofu >= 1.3
  - Google Provider >= 5.12.0

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `domain` | Fully qualified domain name for the zone | `"dev.example.io."` |
| `project_id` | GCP project ID (via dependency) | `"perimeter-dns-infra"` |

### Optional Parameters with Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `type` | `"public"` | Zone type (public/private) |
| `description` | `"Managed by Terragrunt"` | Zone description |
| `ttl` | `300` | Default TTL for records |
| `enable_dnssec` | `true` | Enable DNSSEC for the zone |
| `dnssec_algorithm` | `"rsasha256"` | DNSSEC signing algorithm |
| `recordsets` | `[]` | DNS records to create |
| `labels` | `{}` | Resource labels |
| `visibility` | `"public"` | Zone visibility |
| `private_visibility_config_networks` | `[]` | VPC self links with access to private zones |

## Directory Structure

Cloud DNS configurations follow a global deployment pattern. Private zones that need to be reachable from VPN clients now live in the hub project, while environment-specific zones remain alongside their owning projects:

```
live/
└── non-production/
    ├── hub/
    │   └── dns-hub/                        # Shared DNS project for VPN-facing zones
    │       ├── project/
    │       └── global/cloud-dns/
    │           ├── dns.hcl                 # Shared DNS defaults
    │           └── dev-example-io-internal/ # Shared private zone
    │               └── terragrunt.hcl
    └── perimeter/
        └── dns-infra/                      # Environment specific DNS project
            └── global/cloud-dns/
                ├── dns.hcl
                └── <project>-dev-example-io-internal/
                    └── terragrunt.hcl
```

## Usage Example

### Basic Zone Configuration

```hcl
# File: live/non-production/perimeter/dns-infra/global/cloud-dns/example-com/terragrunt.hcl

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
  # Zone configuration
  domain      = "example.com."
  description = "Public DNS zone for example.com"

  # DNS Records
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
      records = [
        "10 mail.example.com.",
        "20 mail2.example.com."
      ]
    },
    {
      name    = ""
      type    = "TXT"
      ttl     = 300
      records = [
        "\"v=spf1 include:_spf.google.com ~all\"",
        "\"google-site-verification=VERIFICATION_CODE\""
      ]
    }
  ]

  # Zone-specific labels
  labels = {
    domain     = "example-com"
    visibility = "public"
    dnssec     = "enabled"
  }
}
```

### Shared DNS Configuration

```hcl
# File: live/non-production/perimeter/dns-infra/global/cloud-dns/dns.hcl

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
```

### Hub Private Zone (VPN-visible)

```hcl
# File: live/non-production/hub/dns-hub/global/cloud-dns/dev-example-io-internal/terragrunt.hcl

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

dependency "vpn_gateway_network" {
  config_path = "${get_repo_root()}/live/non-production/hub/vpn-gateway/vpc-network"
}

inputs = {
  domain      = "dev.example.io."
  description = "Shared private zone resolvable by VPN clients"
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

## DNS Records Configuration

### Supported Record Types

The template supports all standard DNS record types:

| Type | Purpose | Example |
|------|---------|---------|
| A | IPv4 address | `["192.0.2.1"]` |
| AAAA | IPv6 address | `["2001:db8::1"]` |
| CNAME | Canonical name | `["target.example.com."]` |
| MX | Mail exchange | `["10 mail.example.com."]` |
| TXT | Text records | `["\"v=spf1 include:_spf.google.com ~all\""]` |
| NS | Name server | `["ns1.example.com."]` |
| PTR | Pointer | `["host.example.com."]` |
| SRV | Service | `["10 60 5060 sip.example.com."]` |
| CAA | Certificate authority | `["0 issue \"letsencrypt.org\""]` |

### Record Configuration Examples

```hcl
recordsets = [
  # A record for root domain
  {
    name    = ""
    type    = "A"
    ttl     = 300
    records = ["34.102.136.180"]
  },

  # CNAME for subdomain
  {
    name    = "api"
    type    = "CNAME"
    ttl     = 300
    records = ["api-gateway.example.com."]
  },

  # Multiple MX records with priority
  {
    name    = ""
    type    = "MX"
    ttl     = 300
    records = [
      "1 aspmx.l.google.com.",
      "5 alt1.aspmx.l.google.com.",
      "5 alt2.aspmx.l.google.com.",
      "10 alt3.aspmx.l.google.com.",
      "10 alt4.aspmx.l.google.com."
    ]
  },

  # SPF and DKIM records
  {
    name    = ""
    type    = "TXT"
    ttl     = 300
    records = [
      "\"v=spf1 include:_spf.google.com include:sendgrid.net ~all\""
    ]
  },

  # CAA record for SSL certificate issuance
  {
    name    = ""
    type    = "CAA"
    ttl     = 300
    records = [
      "0 issue \"letsencrypt.org\"",
      "0 issuewild \"letsencrypt.org\"",
      "0 iodef \"mailto:security@example.com\""
    ]
  }
]
```

## DNSSEC Configuration

### Enabling DNSSEC

DNSSEC is enabled by default in the template. The configuration includes:

```hcl
dnssec_config = {
  state = "on"
  default_key_specs = [
    {
      algorithm  = "rsasha256"  # or "rsasha512", "ecdsap256sha256", "ecdsap384sha384"
      key_type   = "keySigning"
      key_length = 2048
    },
    {
      algorithm  = "rsasha256"
      key_type   = "zoneSigning"
      key_length = 1024
    }
  ]
}
```

### DNSSEC Key Algorithms

| Algorithm | Key Signing | Zone Signing | Security Level |
|-----------|------------|--------------|----------------|
| rsasha256 | 2048 bits | 1024 bits | Standard |
| rsasha512 | 2048 bits | 1024 bits | High |
| ecdsap256sha256 | 256 bits | 256 bits | Modern |
| ecdsap384sha384 | 384 bits | 384 bits | Very High |

### Disabling DNSSEC

To disable DNSSEC for a specific zone:

```hcl
inputs = {
  enable_dnssec = false
  # ... other configuration
}
```

## Private DNS Zones

For private DNS zones accessible only within your VPC:

```hcl
inputs = {
  type = "private"
  domain = "internal.example.com."

  # VPC networks that can query this zone
  private_visibility_config_networks = [
    dependency.network.outputs.network_self_link
  ]
}
```

## Cloud DNS Peering Zones

Use `_common/templates/cloud_dns_peering.hcl` to expose a producer VPC's private zone to a consumer project (for example, the `vpn-gateway` project that services VPN clients).

```hcl
include "dns_peering_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_dns_peering.hcl"
  merge_strategy = "deep"
}

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

## Dependencies

The Cloud DNS template automatically manages these dependencies:

1. **Project Dependency**: References the project for the DNS zone
2. **Network Dependency** (for private zones): VPC network access configuration

## Best Practices

### 1. Zone Naming Convention
- Use fully qualified domain names (FQDN) with trailing dot
- Example: `example.com.` not `example.com`

### 2. TTL Values
- Use shorter TTLs (300-600) during migrations
- Use longer TTLs (3600-86400) for stable production records

### 3. DNSSEC Implementation
- Always enable for public zones
- Use appropriate key algorithms based on security requirements
- Monitor DNSSEC validation status

### 4. Record Management
- Group related records together
- Use CNAME records for flexibility
- Implement SPF, DKIM, and DMARC for email domains

### 5. Security
- Deploy DNS zones in dedicated perimeter project
- Use IAM bindings for access control
- Enable audit logging for DNS changes

## Integration with GitHub Actions

The Cloud DNS resources are automatically validated and deployed through GitHub Actions:

### PR Validation
- Triggered on changes to `live/**/global/cloud-dns/**` or `_common/templates/cloud_dns.hcl`
- Validates DNS zone configuration
- Checks for record conflicts

### Automatic Deployment
- Deploys DNS changes after PR merge
- Respects dependency order (project -> DNS zone -> records)
- Provides deployment status in GitHub

## Troubleshooting

### Common Issues and Solutions

#### Zone Creation Fails
**Problem**: "Error creating DNS ManagedZone: googleapi: Error 409"
**Solution**: Zone already exists. Import it:
```bash
terragrunt import google_dns_managed_zone.dns_zone projects/PROJECT_ID/managedZones/ZONE_NAME
```

#### DNSSEC Validation Errors
**Problem**: "DNSSEC validation failed"
**Solution**:
1. Check DS records at parent zone
2. Verify key algorithm compatibility
3. Wait for DNS propagation (up to 48 hours)

#### Record Conflicts
**Problem**: "CNAME and other records cannot coexist"
**Solution**: Remove conflicting A/AAAA records before adding CNAME

#### Private Zone Not Resolving
**Problem**: VMs cannot resolve private zone records
**Solution**:
1. Verify VPC network is authorized
2. Check VM is using Google Cloud DNS (169.254.169.254)
3. Ensure private Google access is enabled

#### Module Version Errors
**Problem**: "Module not found at version v6.0.0"
**Solution**: Ensure `_common/common.hcl` has `cloud_dns = "v6.0.0"`

### Debug Commands

```bash
# List DNS zones
gcloud dns managed-zones list --project=perimeter-dns-infra

# Describe shared VPN-facing zone
gcloud dns managed-zones describe dev-example-io-internal \
  --project=dns-hub

# List records in zone
gcloud dns record-sets list \
  --zone=dev-example-io-internal \
  --project=dns-hub

# Test DNS resolution (from VPN client)
dig @10.11.2.10 development.dev.example.io
nslookup development.dev.example.io 10.11.2.10

# Verify private visibility
gcloud dns managed-zones describe dev-example-io-internal \
  --project=dns-hub \
  --format="get(privateVisibilityConfig.networks[].networkUrl)"
```
## Related Documentation

- [Network Architecture](NETWORK_ARCHITECTURE.md) - Overall network design including DNS
- [Module Versioning](MODULE_VERSIONING.md) - Module version management
- [Configuration Templates](CONFIGURATION_TEMPLATES.md) - Template system overview

## References

- [Google Cloud DNS Documentation](https://cloud.google.com/dns/docs)
- [Terraform Google Cloud DNS Module](https://github.com/terraform-google-modules/terraform-google-cloud-dns)
- [DNSSEC Best Practices](https://cloud.google.com/dns/docs/dnssec)
- [DNS Record Types Reference](https://cloud.google.com/dns/docs/records)
