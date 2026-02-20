<!-- Space: PE -->
<!-- Title: Cloud Armor Template -->
<!-- Parent: Networking Resources -->
<!-- Label: template -->
<!-- Label: cloud-armor -->
<!-- Label: security -->
<!-- Label: load-balancer -->
<!-- Label: ip-allowlist -->
<!-- Label: howto -->
<!-- Label: intermediate -->

# Cloud Armor Template

This document describes the Cloud Armor configuration pattern for deploying Google Cloud Armor security policies to restrict access to External Application Load Balancers by source IP.

## Overview

VPC firewall rules do **not** apply to traffic arriving at an External Application Load Balancer frontend. The correct mechanism for IP-based access control on LBs is **Google Cloud Armor**, which evaluates source IPs before forwarding requests to backends.

Module: [GoogleCloudPlatform/terraform-google-cloud-armor](https://github.com/GoogleCloudPlatform/terraform-google-cloud-armor) v7.0.0.

Key capabilities:
- Default-deny security policies
- IP allowlisting with CIDR precision
- Per-backend policy attachment (not all-or-nothing)
- Priority-based rule evaluation
- Custom 403 responses for blocked traffic

## Module Source

```
git::https://github.com/GoogleCloudPlatform/terraform-google-cloud-armor.git?ref=v7.0.0
```

## Version Pin

The version is pinned in `_common/common.hcl`:

```hcl
module_versions = {
  cloud_armor = "v7.0.0"
}
```

## Template

**Location**: `_common/templates/cloud_armor.hcl`

The template sets the policy type to `CLOUD_ARMOR` and defaults to `deny(403)`:

```hcl
terraform {
  source = "git::https://github.com/GoogleCloudPlatform/terraform-google-cloud-armor.git?ref=${include.base.locals.module_versions.cloud_armor}"
}

inputs = {
  type                = "CLOUD_ARMOR"
  default_rule_action = "deny(403)"
}
```

> **Note**: The template no longer needs manual `locals` to read `common.hcl`. Module versions are available via `include.base.locals.module_versions` when `base.hcl` is included with `expose = true` in the resource file.

## Required Inputs

| Input | Type | Description | Example |
|-------|------|-------------|---------|
| `project_id` | string | GCP project ID | `"fn-dev-01-a"` |
| `name` | string | Security policy name | `"fn-dev-01-cloud-run-lb-policy"` |
| `security_rules` | map | Allow/deny rules with priorities | See below |

## Security Rules Structure

```hcl
security_rules = {
  "rule-name" = {
    action      = "allow"           # or "deny(403)"
    priority    = 1000              # lower = evaluated first
    description = "Human-readable description"
    src_ip_ranges = [
      "1.2.3.4/32",
      "5.6.7.0/24",
    ]
  }
}
```

## Basic Usage

Office + VPN IP allowlist for a Cloud Run load balancer:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_armor_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_armor.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path                             = "../../project"
  mock_outputs                            = { project_id = "mock-project-id" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  project_id          = dependency.project.outputs.project_id
  name                = "my-project-cloud-run-lb-policy"
  default_rule_action = "deny(403)"

  security_rules = {
    "allow-office-and-vpn" = {
      action      = "allow"
      priority    = 1000
      description = "Allow office IPs and VPN server"
      src_ip_ranges = [
        "198.51.100.42/32",   # Office 1
        "198.51.100.44/32",   # Office 2
        "35.214.48.26/32",    # VPN server
      ]
    }
  }
}
```

## Per-Backend Attachment

Cloud Armor policies are attached **per backend**, not per LB. The `serverless_negs` module (v12.0.0) natively supports `security_policy = optional(string, null)` on each backend.

In the load balancer `terragrunt.hcl`, add a dependency on the Cloud Armor resource and set `security_policy` on each backend that should be protected:

```hcl
dependency "cloud_armor" {
  config_path = "../../../cloud-armor/cloud-run-lb-policy"
  mock_outputs = {
    policy = { self_link = "projects/mock/global/securityPolicies/mock-policy" }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  backends = {
    my-api-service = {
      # ... existing config ...
      security_policy = dependency.cloud_armor.outputs.policy.self_link
    }
    my-webhook = {
      # ... existing config ...
      # No security_policy -- webhook must accept external callbacks
    }
  }
}
```

## Webhook Exception Pattern

Some backends (e.g. external API webhook callbacks) must remain accessible from external services that do not publish static IPs. For these backends:

1. **Do not** attach a `security_policy`
2. Rely on application-level authentication (HMAC signature validation, API keys)
3. Document the exception clearly in code comments
4. Consider adding the external service's IPs to a Cloud Armor policy once they publish a stable IP list

## CI/CD Integration

| Setting | Value |
|---------|-------|
| Resource type | `cloud-armor` |
| Dependencies | `projects` |
| Path pattern | `live/**/cloud-armor/**` |
| Config file | `.github/workflow-config/resource-definitions.yml` |

The `load-balancer` resource type depends on `cloud-armor`, so the CI/CD engine deploys the policy before updating backends.

## Dependencies

| Dependency | Required | Description |
|------------|----------|-------------|
| Project | Yes | GCP project must exist |

## Best Practices

- **Default deny**: Always set `default_rule_action = "deny(403)"` and explicitly allow known IPs.
- **CIDR precision**: Use `/32` for individual IPs to avoid accidentally allowing adjacent addresses.
- **Separate policies per LB**: Name policies to match their load balancer (e.g. `fn-dev-01-cloud-run-lb-policy`).
- **Document IP sources**: Comment each CIDR with its purpose (office, VPN, partner).
- **Webhook exceptions**: Leave webhook backends without a policy and rely on HMAC/API-key validation.
- **Priority spacing**: Use priorities in increments of 1000 to leave room for future rules.

## Troubleshooting

### 403 Forbidden -- Cloud Armor vs Cloud Run IAM

If a request returns 403, determine whether the block is from Cloud Armor or Cloud Run IAM:

```bash
# Check Cloud Armor logs (shows matched rule)
gcloud logging read 'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.name!=""' \
  --project=fn-dev-01-a --limit=10

# If the log shows enforcedSecurityPolicy.outcome="DENY", Cloud Armor blocked the request.
# If there's no Cloud Armor log entry, the 403 is from Cloud Run IAM (missing allUsers invoker).
```

### Verify Policy Rules

```bash
gcloud compute security-policies describe fn-dev-01-cloud-run-lb-policy \
  --project=fn-dev-01-a
```

### Test from Allowed IP

```bash
curl -I https://api.fn-dev-01.uat.example.io/api/health
# Expected: 200 or application-level response (not 403)
```

### Test from Non-Allowed IP

```bash
# From a non-allowed network:
curl -I https://api.fn-dev-01.uat.example.io/api/health
# Expected: 403 Forbidden
```

## References

- [Google Cloud Armor documentation](https://cloud.google.com/armor/docs)
- [terraform-google-cloud-armor module](https://github.com/GoogleCloudPlatform/terraform-google-cloud-armor)
- [Load Balancer Template](LOAD_BALANCER_TEMPLATE.md)
- [Configuration Templates Overview](CONFIGURATION_TEMPLATES.md)
