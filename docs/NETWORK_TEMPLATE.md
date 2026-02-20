# Network Template

This document provides detailed information about the Network template available in the Terragrunt GCP infrastructure.

## Overview

The Network template (`_common/templates/network.hcl`) provides a standardized approach to deploying Google Cloud VPC networks using the [terraform-google-network](https://github.com/terraform-google-modules/terraform-google-network) module. It ensures consistent network configuration, security best practices, and environment-aware settings.

## Features

- Environment-aware network configuration
- Standardized VPC and subnet creation
- Automatic firewall rule management
- Secondary IP range support
- Flow logs and private Google access
- Consistent naming and labeling

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `project_id` | GCP project ID | `"project-id"` |
| `network_name` | Name of the VPC network | `"vpc-network"` |
| `subnets` | List of subnets to create | See subnet configuration |

### Optional Parameters with Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `routing_mode` | `"REGIONAL"` | VPC routing mode |
| `shared_vpc_host` | `false` | Enable shared VPC hosting |
| `delete_default_internet_gateway_routes` | `false` | Remove default routes |
| `firewall_rules` | `[]` | Custom firewall rules |

## Directory Structure

VPC Network configurations are located within the region directories following this pattern:

```
live/
└── non-production/
    └── development/
        └── dp-dev-01/
            └── europe-west2/
                └── vpc-network/               # VPC Network configuration
                    └── terragrunt.hcl
```

**Note:** The directory name follows the pattern `{prefix}-{name}-vpc-network` to ensure workflow activation patterns match correctly.

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

  # Environment-specific routing
  routing_mode = include.base.locals.merged.environment_type == "production" ? "GLOBAL" : "REGIONAL"
}
```

### Advanced Usage

#### Multiple Subnets with Secondary Ranges

```hcl
inputs = merge(
  # ... other configuration ...
  {
    subnets = [
      {
        subnet_name           = "main-subnet"
        subnet_ip             = "10.0.1.0/24"
        subnet_region         = include.base.locals.region
        subnet_private_access = "true"
        subnet_flow_logs      = "true"
      },
      {
        subnet_name           = "secondary-subnet"
        subnet_ip             = "10.0.2.0/24"
        subnet_region         = include.base.locals.region
        subnet_private_access = "true"
        subnet_flow_logs      = "false"
      }
    ]
    
    secondary_ranges = {
      "main-subnet" = [
        {
          range_name    = "pods"
          ip_cidr_range = "10.1.0.0/16"
        },
        {
          range_name    = "services"
          ip_cidr_range = "10.2.0.0/16"
        }
      ]
    }
  }
)
```

#### Custom Firewall Rules

```hcl
inputs = merge(
  # ... other configuration ...
  {
    firewall_rules = [
      {
        name          = "allow-ssh"
        description   = "Allow SSH access"
        direction     = "INGRESS"
        ranges        = ["10.0.0.0/8"]
        source_tags   = []
        target_tags   = ["ssh-allowed"]
        allow = [{
          protocol = "tcp"
          ports    = ["22"]
        }]
        deny = []
      },
      {
        name          = "allow-http-https"
        description   = "Allow HTTP and HTTPS"
        direction     = "INGRESS"
        ranges        = ["0.0.0.0/0"]
        source_tags   = []
        target_tags   = ["web-server"]
        allow = [{
          protocol = "tcp"
          ports    = ["80", "443"]
        }]
        deny = []
      }
    ]
  }
)
```

## Best Practices

1. **IP Address Planning** - Plan CIDR blocks to avoid conflicts
2. **Private Google Access** - Enable for instances without external IPs
3. **Flow Logs** - Enable for security monitoring and troubleshooting
4. **Firewall Rules** - Use least privilege principle
5. **Network Naming** - Use consistent naming conventions
6. **Regional Networks** - Use regional routing for better performance
7. **Subnet Design** - Design subnets based on workload requirements

## Deployment Order

1. **Project** → Creates the GCP project
2. **VPC Network** → Creates the network infrastructure
3. **Private Service Access** → Enables private connectivity
4. **Compute Resources** → Deploy VMs and other resources

## Troubleshooting

### Common Issues

1. **CIDR Conflicts**
   - Ensure subnet IP ranges don't overlap
   - Check for conflicts with on-premises networks

2. **Firewall Rule Errors**
   - Verify target tags match compute instance tags
   - Check port ranges are correctly formatted

3. **Private Google Access Issues**
   - Ensure Cloud NAT is configured for outbound access
   - Verify private Google access is enabled on subnets

### Validation Commands

```bash
# List VPC networks
gcloud compute networks list --project=PROJECT_ID

# List subnets
gcloud compute networks subnets list --project=PROJECT_ID

# List firewall rules
gcloud compute firewall-rules list --project=PROJECT_ID
```

## Module Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `network_name` | Name of the VPC network | `"vpc-network"` |
| `network_self_link` | Self-link of the VPC network | `"projects/project/global/networks/vpc"` |
| `subnets_names` | Names of created subnets | `["subnet-01", "subnet-02"]` |
| `subnets_self_links` | Self-links of created subnets | `["projects/project/regions/region/subnetworks/subnet"]` |

## Security Considerations

1. **Network Segmentation** - Use multiple subnets for different tiers
2. **Firewall Rules** - Apply principle of least privilege
3. **Private Access** - Use private Google access instead of external IPs
4. **VPC Flow Logs** - Enable for security monitoring
5. **Network Tags** - Use tags for granular firewall control

## References

- [terraform-google-network module](https://github.com/terraform-google-modules/terraform-google-network)
- [Google Cloud VPC documentation](https://cloud.google.com/vpc/docs)
- [VPC Network Best Practices](https://cloud.google.com/vpc/docs/best-practices)
- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/) 
