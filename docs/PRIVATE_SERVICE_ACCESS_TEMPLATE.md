# Private Service Access Template

This document provides detailed information about the Private Service Access template available in the Terragrunt GCP infrastructure.

## Overview

The Private Service Access template (`_common/templates/private_service_access.hcl`) provides a standardized approach to configuring private service access for Google Cloud services, particularly Cloud SQL, using the [Coalfire terraform-google-private-service-access](https://github.com/Coalfire-CF/terraform-google-private-service-access) module. This template ensures consistent configuration and secure private connectivity between your VPC and Google-managed services.

## Features

- Environment-aware IP range allocation (production vs. non-production)
- Automatic service networking peering setup
- Standardized naming conventions
- Support for Cloud SQL and other Google services
- Labeling for resource management and cost allocation
- Integration with existing network infrastructure

## Configuration Options

### Required Parameters

| Parameter      | Description                                 | Example                |
|---------------|---------------------------------------------|------------------------|
| `project_id`  | GCP project ID                              | `project-id`           |
| `network`     | VPC network self-link                       | `projects/.../networks/vpc-01` |

### Optional Parameters with Defaults

| Parameter      | Default (non-prod)         | Default (prod)           | Description |
|----------------|---------------------------|--------------------------|-------------|
| `private_ip_cidr` | `10.11.0.0/16`         | `10.1.0.0/16`            | IP range for private services |
| `private_ip_name` | `private-service-access` | `private-service-access` | Name of the IP range |
| `service`      | `servicenetworking.googleapis.com` | Same        | Google service to peer with |
| `labels`       | See template              | See template             | Resource labels |

## Directory Structure

Private Service Access configurations are located within the region directories following this pattern:

```
live/
└── non-production/
    └── development/
        └── dev-01/
            └── europe-west2/
                └── private-service-access/  # Private Service Access configuration
                    └── terragrunt.hcl
```

**Note:** The directory name follows the pattern `{prefix}-{name}-psa` to ensure workflow activation patterns match correctly.

## Usage

### Basic Implementation

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "private_service_access_template" {
  path = "${get_parent_terragrunt_dir()}/_common/templates/private_service_access.hcl"
}

dependency "network" {
  config_path = "../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock-project/global/networks/mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  skip_outputs = true
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  skip_outputs = true
}

locals {
  merged_vars = merge(
    try(read_terragrunt_config(find_in_parent_folders("account.hcl")).locals, {}),
    try(read_terragrunt_config(find_in_parent_folders("env.hcl")).locals, {}),
    try(read_terragrunt_config(find_in_parent_folders("project.hcl")).locals, {}),
    try(read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals, {})
  )

  name_prefix = try(local.merged_vars.name_prefix, "org")
  private_ip_range_name = "${local.name_prefix}-${local.merged_vars.project}-private-service-access"
}

inputs = merge(
  try(read_terragrunt_config("${get_parent_terragrunt_dir()}/_common/templates/private_service_access.hcl").inputs, {}),
  local.merged_vars,
  {
    project_id           = try(dependency.project.outputs.project_id, "mock-project-id")
    network              = try(dependency.network.outputs.network_self_link, "projects/mock-project/global/networks/mock-network")
    private_ip_name      = local.private_ip_range_name
    environment_type     = try(local.merged_vars.environment_type, "non-production")
    
    labels = merge(
      {
        component        = "private-service-access"
        environment      = try(local.merged_vars.environment, "unknown")
        environment_type = try(local.merged_vars.environment_type, "non-production")
        name_prefix      = local.name_prefix
        purpose          = "cloud-sql-peering"
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
  }
)
```

### Integration with Cloud SQL

After setting up private service access, you can reference it in your Cloud SQL configuration:

```hcl
# In your SQL Server terragrunt.hcl
dependency "private_service_access" {
  config_path = "../../network/private-service-access"
  mock_outputs = {
    google_compute_global_address_name = "mock-private-ip-range"
    address                           = "10.11.0.0"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  ip_configuration = {
    private_network     = dependency.network.outputs.network_self_link
    require_ssl         = true
    ipv4_enabled        = false
    allocated_ip_range  = dependency.private_service_access.outputs.google_compute_global_address_name
    authorized_networks = []
  }
}
```

## Environment-Specific Configuration

The template automatically selects appropriate IP ranges based on the environment:

### Production Environment
- **IP Range**: `10.1.0.0/16`
- **Size**: Larger range for production workloads
- **Description**: "for production Cloud SQL and other Google services"

### Non-Production Environment
- **IP Range**: `10.11.0.0/16`
- **Size**: Smaller range for development/testing
- **Description**: "for non-production Cloud SQL and other Google services"

## Prerequisites

Before using this template, ensure:

1. **VPC Network**: A VPC network must exist and be accessible
2. **Service Networking API**: The `servicenetworking.googleapis.com` API must be enabled
3. **IAM Permissions**: The service account must have:
   - `roles/servicenetworking.networksAdmin`
   - `roles/compute.networkAdmin`
4. **IP Range Planning**: Ensure the allocated IP ranges don't conflict with existing subnets

## Best Practices

1. **Deploy Before SQL**: Always deploy private service access before creating Cloud SQL instances
2. **Use Dependencies**: Set up proper Terragrunt dependencies to ensure correct deployment order
3. **Environment Separation**: Use different IP ranges for different environments
4. **Consistent Naming**: Use the organization's naming prefix for all resources
5. **Monitor Usage**: Track IP range utilization to avoid exhaustion

## Troubleshooting

### Common Issues

1. **IP Range Conflicts**
   - Ensure private service access ranges don't overlap with VPC subnets
   - Check existing private service connections

2. **API Not Enabled**
   - Verify `servicenetworking.googleapis.com` is enabled
   - Check project-level API activation

3. **Permission Denied**
   - Verify service account has required networking permissions
   - Check IAM bindings at project level

4. **Peering Already Exists**
   - Only one private service access connection per VPC network
   - Check for existing connections before creating new ones

### Validation Commands

```bash
# Check existing private service connections
gcloud services vpc-peerings list --network=NETWORK_NAME

# Verify service networking API is enabled
gcloud services list --enabled --filter="name:servicenetworking.googleapis.com"

# Check allocated IP ranges
gcloud compute addresses list --global --filter="purpose:VPC_PEERING"
```

## Module Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `google_compute_global_address_name` | Name of the allocated IP range | `org-project-private-service-access` |
| `address` | First IP of the reserved range | `10.11.0.0` |

## References

- [Coalfire terraform-google-private-service-access](https://github.com/Coalfire-CF/terraform-google-private-service-access)
- [Google Cloud Private Service Access](https://cloud.google.com/vpc/docs/private-service-access)
- [Cloud SQL Private IP](https://cloud.google.com/sql/docs/mysql/private-ip)
- [Service Networking API](https://cloud.google.com/service-infrastructure/docs/service-networking/getting-started) 
