<!-- Space: PE -->
<!-- Title: VPC Peering Connectivity Guide -->
<!-- Parent: Network Design -->
<!-- Label: network -->
<!-- Label: vpc-peering -->
<!-- Label: guide -->
<!-- Label: operations -->
<!-- Label: connectivity -->

# VPC Peering Connectivity Guide (Primary)

This guide explains the primary network connectivity design based on Google Cloud VPC Network Peering, how it replaces NCC for day-to-day connectivity, and how it is implemented and operated in this repository.

For the combined peering + VPN Gateway architecture overview, see `docs/VPC_PEERING_AND_VPN_GATEWAY.md`.

## Why VPC Peering
- Simple, low-ops connectivity between VPCs with no control plane
- Zero hourly cost (egress charged per GB)
- Predictable behavior; security controls via firewall rules
- Works seamlessly with VPN clients when client pools are subnets in the vpn-gateway VPC

Limitations to keep in mind:
- Non-transitive (A<->B and A<->C does not imply B<->C)
- Exchanges all subnet routes; use firewall rules for access control
- Private Service Access (PSA) endpoints are not reachable across peering; use Cloud SQL Auth Proxy/PSC or place clients in target VPC
- GKE Pod and Service secondary CIDRs are reachable over peering (subject to firewall). Internal Load Balancers are also reachable across peering (subject to firewall and routing).

## Repository Layout
- Reusable template: `_common/templates/vpc_peering.hcl` (wraps `terraform-google-modules/network/google//modules/network-peering` at `${include.base.locals.module_versions.network}`)
- Live resources (one directory per peer):
  - `live/non-production/hub/vpn-gateway/global/networking/vpc-peering/dev-01/terragrunt.hcl`
  - `live/non-production/hub/vpn-gateway/global/networking/vpc-peering/data-staging/terragrunt.hcl`

## Terragrunt Pattern
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "tpl" {
  path           = "${get_repo_root()}/_common/templates/vpc_peering.hcl"
  merge_strategy = "deep"
}

dependency "vpn_vpc"  { config_path = "../../../../vpc-network" }
dependency "peer_vpc" { config_path = "<path-to-peer>/vpc-network" }

inputs = {
  local_network = dependency.vpn_vpc.outputs.network_self_link
  peer_network  = dependency.peer_vpc.outputs.network_self_link

  export_local_custom_routes                = false
  export_peer_custom_routes                 = false
  export_local_subnet_routes_with_public_ip = false
  export_peer_subnet_routes_with_public_ip  = false
  stack_type                                = "IPV4_ONLY"
}
```

## CI/CD Integration
- New resource type: `vpc-peering` added to both PR and Apply engines
- Change detection:
  - Direct file changes under `live/**/vpc-peering/**` trigger the jobs
  - Template changes `_common/templates/vpc_peering.hcl` fan out to all peering resources
- Ordering and gating:
  - PR: `validate-vpc-peering` runs after folders/projects/VPC validation (even if VPC had no diff)
  - Apply: `apply-vpc-peering` runs after folders/projects/VPC apply (success or skipped); does not require a VPC diff
- Module limitation handled: only one peering to the same local VPC can be applied at a time; the engine processes sequentially

## Operational Tips
- Validate and plan peering changes from the peering directory:
  - `terragrunt run validate`
  - `terragrunt run plan`
- Firewall rules enforce access controls for VPN clients (10.11.100.0/24, 10.11.101.0/24, 10.11.111.0/24)
- Remember PSA limitation across peering; use proxies or run clients inside target VPC

## Legacy NCC
- NCC hub/spokes remain in the repo and workflows for reference
- Prefer VPC Peering for new connectivity
- See also: `docs/NCC_AND_VPN_GATEWAY.md` (legacy) and `docs/VPC_PEERING_AND_VPN_GATEWAY.md` (design)
