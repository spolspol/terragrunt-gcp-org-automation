# Network Template

The Network template (`_common/templates/network.hcl`) creates VPC networks, subnets, and firewall rules using the [terraform-google-network](https://github.com/terraform-google-modules/terraform-google-network) module (v12.0.0). Networks are the third resource in the dependency chain, created after folders and projects.

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `project_id` | GCP project ID | `"project-id"` |
| `network_name` | Name of the VPC network | `"vpc-network"` |
| `subnets` | List of subnets to create | See subnet configuration |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `routing_mode` | `"REGIONAL"` | VPC routing mode |
| `shared_vpc_host` | `false` | Enable shared VPC hosting |
| `delete_default_internet_gateway_routes` | `false` | Remove default routes |
| `firewall_rules` | `[]` | Custom firewall rules |

## Directory Structure

```
live/non-production/development/
├── platform/
│   └── dp-dev-01/
│       └── vpc-network/           # Platform VPC (5 subnets, GKE ranges)
│           └── terragrunt.hcl
└── functions/
    └── fn-dev-01/
        └── vpc-network/           # Functions VPC (private + serverless subnets)
            └── terragrunt.hcl
```

## Usage

### Basic Implementation

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "network_template" {
  path           = "${get_repo_root()}/_common/templates/network.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  skip_outputs = true
}

inputs = {
  project_id   = try(dependency.project.outputs.project_id, "mock-project-id")
  network_name = "${include.base.locals.merged.name_prefix}-${include.base.locals.merged.project}-vpc"

  subnets = [
    {
      subnet_name           = "${include.base.locals.merged.name_prefix}-${include.base.locals.merged.project}-subnet-01"
      subnet_ip             = "10.0.1.0/24"
      subnet_region         = include.base.locals.region
      subnet_private_access = "true"
      subnet_flow_logs      = "true"
    }
  ]

  routing_mode = include.base.locals.merged.environment_type == "production" ? "GLOBAL" : "REGIONAL"
}
```

### Multiple Subnets with Secondary Ranges (GKE)

```hcl
inputs = {
  subnets = [
    {
      subnet_name           = "main-subnet"
      subnet_ip             = "10.0.1.0/24"
      subnet_region         = include.base.locals.region
      subnet_private_access = "true"
      subnet_flow_logs      = "true"
    }
  ]

  secondary_ranges = {
    "main-subnet" = [
      { range_name = "pods",     ip_cidr_range = "10.1.0.0/16" },
      { range_name = "services", ip_cidr_range = "10.2.0.0/16" }
    ]
  }
}
```

## Deployment Order

1. **Project** -- creates the GCP project
2. **VPC Network** -- creates network infrastructure
3. **Private Service Access** -- enables private connectivity
4. **Networking** -- Cloud Router, NAT, External IPs, Firewall Rules
5. **Compute Resources** -- VMs, GKE, Cloud Run

## Best Practices

- Plan CIDR blocks carefully to avoid overlaps with peered networks
- Enable Private Google Access and Flow Logs on all subnets
- Use network tags for granular firewall control
- Apply least-privilege firewall rules
- Use regional routing unless cross-region connectivity is required

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| CIDR conflicts | Ensure subnet ranges do not overlap with existing or peered networks |
| Firewall rule errors | Verify target tags match compute instance tags and port format |
| Private Google Access issues | Confirm Cloud NAT is configured and private access is enabled |

```bash
gcloud compute networks list --project=PROJECT_ID
gcloud compute networks subnets list --project=PROJECT_ID
gcloud compute firewall-rules list --project=PROJECT_ID
```

## Module Outputs

| Output | Description |
|--------|-------------|
| `network_name` | Name of the VPC network |
| `network_self_link` | Self-link of the VPC network |
| `subnets_names` | Names of created subnets |
| `subnets_self_links` | Self-links of created subnets |

## References

- [terraform-google-network module](https://github.com/terraform-google-modules/terraform-google-network)
- [Google Cloud VPC documentation](https://cloud.google.com/vpc/docs)
- [VPC Best Practices](https://cloud.google.com/vpc/docs/best-practices)
