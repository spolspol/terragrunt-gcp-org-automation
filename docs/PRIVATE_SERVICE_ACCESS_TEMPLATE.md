# Private Service Access Template

The Private Service Access template (`_common/templates/private_service_access.hcl`) reserves a VPC IP range and peers it with Google-managed services using the [Coalfire terraform-google-private-service-access](https://github.com/Coalfire-CF/terraform-google-private-service-access) module (v1.0.4).

Private Service Access (PSA) is required whenever a managed service -- Cloud SQL, Memorystore, Filestore, or any service that uses VPC Service Networking -- needs to communicate with your VPC over private IP. Without PSA, these services either cannot be created with private networking or must use public endpoints.

## Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `project_id` | GCP project ID | `"project-id"` |
| `network` | VPC network self-link | `"projects/.../networks/vpc-01"` |

### Optional Parameters

| Parameter | Default (non-prod) | Default (prod) | Description |
|-----------|-------------------|----------------|-------------|
| `private_ip_cidr` | `10.11.0.0/16` | `10.1.0.0/16` | IP range for private services |
| `private_ip_name` | `private-service-access` | `private-service-access` | Name of the IP range |
| `service` | `servicenetworking.googleapis.com` | Same | Google service to peer with |
| `labels` | See template | See template | Resource labels |

## When PSA Is Needed

| Service | Requires PSA | Notes |
|---------|-------------|-------|
| Cloud SQL (private IP) | Yes | Most common use case |
| Memorystore (Redis/Memcached) | Yes | Private instance access |
| Filestore | Yes | Shared file storage |
| Cloud Run (VPC connector) | No | Uses Serverless VPC Access instead |
| GKE private cluster | No | Uses separate master CIDR range |

## Directory Structure

```
live/non-production/development/
├── platform/
│   └── dp-dev-01/
│       └── europe-west2/
│           └── private-service-access/    # Platform PSA
│               └── terragrunt.hcl
└── functions/
    └── fn-dev-01/
        └── europe-west2/
            └── networking/
                └── private-service-access/  # Functions PSA
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

include "private_service_access_template" {
  path           = "${get_repo_root()}/_common/templates/private_service_access.hcl"
  merge_strategy = "deep"
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

inputs = {
  project_id       = try(dependency.project.outputs.project_id, "mock-project-id")
  network          = try(dependency.network.outputs.network_self_link, "projects/mock-project/global/networks/mock-network")
  private_ip_name  = "${include.base.locals.merged.name_prefix}-${include.base.locals.merged.project}-private-service-access"
  environment_type = try(include.base.locals.merged.environment_type, "non-production")

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "private-service-access"
      purpose   = "cloud-sql-peering"
    }
  )
}
```

### Integration with Cloud SQL

After PSA is deployed, reference it in Cloud SQL configuration:

```hcl
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

## Environment-Specific IP Ranges

| Environment | IP Range | Description |
|-------------|----------|-------------|
| Production | `10.1.0.0/16` | Larger range for production workloads |
| Non-production | `10.11.0.0/16` | Smaller range for dev/test |

## Prerequisites

1. **VPC Network** must exist and be accessible
2. **Service Networking API** (`servicenetworking.googleapis.com`) must be enabled
3. **IAM Permissions**: `roles/servicenetworking.networksAdmin` and `roles/compute.networkAdmin`
4. **IP Range Planning**: allocated ranges must not conflict with existing subnets

## Best Practices

- Always deploy PSA before creating Cloud SQL or other managed service instances
- Use different IP ranges for different environments to avoid peering conflicts
- Only one PSA connection is allowed per VPC network -- plan the range size accordingly
- Monitor IP range utilisation to avoid exhaustion
- Set up proper Terragrunt dependencies to enforce correct deployment order

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| IP range conflicts | Ensure PSA ranges do not overlap with VPC subnets |
| API not enabled | Verify `servicenetworking.googleapis.com` is enabled |
| Permission denied | Check `roles/servicenetworking.networksAdmin` at project level |
| Peering already exists | Only one PSA connection per VPC -- check existing connections |

```bash
gcloud services vpc-peerings list --network=NETWORK_NAME
gcloud services list --enabled --filter="name:servicenetworking.googleapis.com"
gcloud compute addresses list --global --filter="purpose:VPC_PEERING"
```

## Module Outputs

| Output | Description |
|--------|-------------|
| `google_compute_global_address_name` | Name of the allocated IP range |
| `address` | First IP of the reserved range |

## References

- [Coalfire terraform-google-private-service-access](https://github.com/Coalfire-CF/terraform-google-private-service-access)
- [Google Cloud Private Service Access](https://cloud.google.com/vpc/docs/private-service-access)
- [Cloud SQL Private IP](https://cloud.google.com/sql/docs/mysql/private-ip)
