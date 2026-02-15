# Google Kubernetes Engine (GKE) Configuration

## Overview

This repository supports deployment of Google Kubernetes Engine (GKE) clusters using the terraform-google-kubernetes-engine module with comprehensive security features, enhanced networking capabilities, and environment-specific configurations.

## Current Module Features

### Enhanced Networking
- **DNS Cache**: Improves DNS query performance with node-local DNS caching
- **L4 ILB Subsetting**: Better load balancer traffic distribution
- **Multi-networking**: Support for multiple network interfaces
- **FQDN Network Policy**: Network policies based on domain names
- **Cilium Network Policy**: Advanced eBPF-based networking

### Storage & Performance
- **Storage Pools**: Configure storage pools for improved I/O performance
- **Google Cloud Filestore CSI**: Native Filestore integration
- **GCS FUSE CSI Driver**: Mount GCS buckets as filesystems
- **Fast Socket**: Enhanced networking performance for supported instances
- **GVNIC**: Google Virtual NIC for better network throughput

### Security & Management
- **GKE Backup Agent**: Native backup and restore capabilities
- **Confidential Nodes**: Hardware-based memory encryption
- **Enhanced Workload Identity**: Improved pod-to-GCP authentication
- **Cost Allocation**: Built-in cost tracking and reporting
- **Fleet Management**: Multi-cluster management capabilities

### Operations
- **Stateful HA**: High availability for stateful workloads
- **Managed Prometheus**: Native Prometheus monitoring
- **Component-level logging**: Granular control over logging
- **TPU Support**: Configure TPU topology and placement

### Node Pool Autoscaling
- **Total Node Limits**: Use `total_min_count` and `total_max_count` for cluster-wide limits
- **Location Policy**: `location_policy = "ANY"` prioritizes unused reservations and reduces spot preemption
- **Cost Optimization**: Start with 0 nodes and scale based on demand
- **Spot Instance Support**: Enhanced spot instance management with better availability

### Minimal Configuration Approach

For development environments, this template uses a minimal feature set to reduce complexity and cost while maintaining essential functionality:

#### Features Enabled in Minimal Setup:
- **Private Nodes**: Essential security (nodes use internal IPs)
- **NAT Gateway Integration**: Internet access for private nodes via shared external IP
- **Master Authorized Networks**: IP-based API access control
- **Workload Identity**: Secure pod-to-GCP authentication
- **Horizontal Pod Autoscaling**: Required for cluster autoscaling
- **HTTP Load Balancing**: Basic ingress functionality
- **Spot Instances**: Cost optimization
- **Total Node Limits**: Cluster-wide scaling (0-3 nodes)
- **Daily Maintenance Window**: Simplified maintenance schedule

#### Features Disabled in Minimal Setup:
- **DNS Cache**: Disabled to reduce complexity
- **Cost Allocation Tracking**: Not needed for development
- **L4 ILB Subsetting**: Advanced networking feature
- **GKE Backup Agent**: Not needed for ephemeral development workloads
- **Shielded Nodes**: Security hardening disabled for simplicity
- **Binary Authorization**: Advanced security not needed in dev
- **Network Policies**: Micro-segmentation disabled
- **Advanced Network Policies**: FQDN and Cilium features disabled
- **Managed Prometheus**: Advanced monitoring disabled
- **Filestore CSI**: Storage features not needed

#### Trade-offs:
- **Performance**: Some performance optimizations disabled for simplicity
- **Security**: Advanced security features disabled but core security maintained
- **Monitoring**: Reduced to system components only
- **Cost**: Optimized for minimal resource usage

## Cluster Naming Pattern

### Overview
GKE clusters follow a standardized naming pattern: `{project}-{region:0:3}-{cluster-id}`

### Generic Algorithm
The region abbreviation is generated using a generic algorithm that works across all GCP regions:
- **First letter** of the first region segment
- **First letter** of the second region segment  
- **Last character** of the second region segment

### Examples
| Region | Algorithm | Abbreviation | Example Cluster Name |
|--------|-----------|--------------|---------------------|
| `europe-west2` | `e` + `w` + `2` | `ew2` | `dp-dev-01-ew2-cluster-01` |
| `us-central1` | `u` + `c` + `1` | `uc1` | `dp-dev-01-uc1-cluster-01` |
| `asia-east1` | `a` + `e` + `1` | `ae1` | `dp-dev-01-ae1-cluster-01` |
| `us-west1` | `u` + `w` + `1` | `uw1` | `dp-dev-01-uw1-cluster-01` |

### Implementation
The naming logic is implemented in the cluster's `terragrunt.hcl`:

```hcl
locals {
  # Cluster naming with new pattern: {project}-{region:0:3}-{cluster-id}
  cluster_id = basename(get_terragrunt_dir())  # cluster-01
  # Generic region abbreviation algorithm
  region_parts = split("-", local.merged_vars.region)
  region_abbr = "${substr(local.region_parts[0], 0, 1)}${substr(local.region_parts[1], 0, 1)}${substr(local.region_parts[1], -1, 1)}"
}

inputs = {
  name = "${dependency.project.outputs.project_name}-${local.region_abbr}-${local.cluster_id}"
  # ... other configurations
}
```

### Benefits
- **Consistency**: Uniform naming across all regions
- **Readability**: Clear indication of project, region, and cluster identity
- **Scalability**: Generic algorithm works for any GCP region
- **Uniqueness**: Guaranteed unique cluster names within a project

## NAT Gateway Integration

### Overview
GKE clusters are integrated with NAT Gateway to provide secure internet access for private nodes. This allows nodes to download container images, access external APIs, and communicate with GCP services while maintaining network security.

### Architecture
- **Private Nodes**: GKE nodes use internal IP addresses only
- **NAT Gateway**: Shared external IP for outbound internet access
- **Firewall Rules**: Controlled egress traffic through NAT gateway
- **Cost Optimization**: Shared NAT gateway reduces external IP costs

### Configuration
NAT Gateway integration is configured automatically when clusters are deployed with private nodes:

```hcl
# Node pools are automatically tagged for NAT gateway integration
node_pools_tags = {
  all = ["gke-node", "terragrunt-managed", "nat-enabled", local.merged_vars.environment]
}

# Private node configuration
enable_private_nodes = true
enable_private_endpoint = false  # Public endpoint for development access
```

### Network Requirements
- **NAT Gateway**: Must be deployed in the same VPC as the GKE cluster
- **External IP**: Regional external IP allocated for NAT gateway
- **Firewall Rules**: Egress rules allowing traffic from NAT-enabled nodes
- **Subnets**: GKE subnet must be configured for NAT gateway usage

### Benefits
- **Security**: Nodes have no direct internet access
- **Cost Efficiency**: Shared external IP reduces costs
- **Centralized Control**: All internet traffic goes through NAT gateway
- **Logging**: Comprehensive logging of all outbound traffic

## Maintenance Windows

### Daily Maintenance Window (Recommended)
GKE clusters use daily maintenance windows for optimal availability and compliance with GKE requirements.

#### Configuration
```hcl
# Daily maintenance window configuration
maintenance_start_time = "01:00"  # 1AM UTC daily
# maintenance_end_time and maintenance_recurrence are omitted for daily windows
```

#### Benefits
- **Compliance**: Meets GKE's 4+ hour availability requirement within 48-hour periods
- **Simplicity**: Simple HH:MM format (24-hour)
- **Flexibility**: Daily windows provide more scheduling options
- **Reliability**: Avoids long periods without maintenance opportunities

#### Format Requirements
- **Time Format**: `HH:MM` in 24-hour format
- **Timezone**: UTC
- **Duration**: 4-hour maintenance window available daily
- **Parameters**: Only `maintenance_start_time` is required for daily windows

### Migration from Weekly Windows
If upgrading from weekly maintenance windows:

```hcl
# Remove these parameters for daily windows:
# maintenance_end_time   = "05:00"
# maintenance_recurrence = "FREQ=WEEKLY;BYDAY=SU"

# Keep only:
maintenance_start_time = "01:00"
```

## Usage

### Creating a New GKE Cluster

1. Create the cluster directory:
   ```bash
   mkdir -p live/account/environment/project/region/gke/cluster-name
   ```

2. Create `terragrunt.hcl` using the template (see examples below)

3. Apply the configuration:
   ```bash
   cd live/account/environment/project/region/gke/cluster-name
   terragrunt run apply
   ```

### Connecting to the Cluster

```bash
gcloud container clusters get-credentials CLUSTER_NAME \
  --region REGION \
  --project PROJECT_ID
```

## Configuration

### Required Dependencies
- VPC Network with secondary ranges for pods and services
- Project with required APIs enabled
- Google Provider version >= 6.38.0

### Environment-Specific Settings

#### Production
- Larger node pools (n2-standard-4)
- No spot instances
- Restricted master authorized networks
- Private endpoint enabled
- GKE backup agent enabled
- GVNIC enabled for performance
- Cost allocation tracking

#### Non-Production
- Smaller node pools (e2-standard-2)
- Spot instances for cost savings
- Open master authorized networks for development
- Public endpoint enabled
- DNS cache enabled
- Minimal addons for cost optimization

## Module Reference

Using terraform-google-kubernetes-engine (current version as specified in `_common/common.hcl`)

Key parameters:
- `enable_private_nodes`: Use internal IPs for nodes
- `enable_workload_identity`: Pod-to-GCP authentication
- `enable_binary_authorization`: Container image verification
- `node_pools`: Configure compute resources
- `dns_cache`: DNS caching (boolean)
- `gke_backup_agent_config`: Backup capabilities (object with enabled field)
- `enable_cost_allocation`: Cost tracking

## Example Configuration

### Development Cluster

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "project" {
  path = find_in_parent_folders("project.hcl")
}

include "region" {
  path = find_in_parent_folders("region.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "gke_template" {
  path = "${get_repo_root()}/_common/templates/gke.hcl"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )

  # Cluster naming with new pattern: {project}-{region:0:3}-{cluster-id}
  cluster_id = basename(get_terragrunt_dir())  # cluster-01
  # Generic region abbreviation algorithm
  region_parts = split("-", local.merged_vars.region)
  region_abbr = "${substr(local.region_parts[0], 0, 1)}${substr(local.region_parts[1], 0, 1)}${substr(local.region_parts[1], -1, 1)}"
}

dependency "vpc-network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name       = "mock-network"
    network_self_link  = "projects/mock-project/global/networks/mock-network"
    subnets_self_links = ["projects/mock-project/regions/europe-west2/subnetworks/mock-subnet"]
    subnets_names      = ["mock-subnet"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id            = "mock-project-id"
    project_name          = "mock-project"
    service_account_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

inputs = merge(
  {
    # Required parameters
    project_id       = dependency.project.outputs.project_id
    name            = "${dependency.project.outputs.project_name}-${local.region_abbr}-${local.cluster_id}"
    region          = local.merged_vars.region
    zones           = ["${local.merged_vars.region}-a", "${local.merged_vars.region}-b", "${local.merged_vars.region}-c"]
    network         = dependency.vpc-network.outputs.network_name
    subnetwork      = dependency.vpc-network.outputs.subnets_names[0]
    
    # Secondary ranges for pods and services
    ip_range_pods     = "gke-pods"
    ip_range_services = "gke-services"
    
    # Environment-specific configuration
    environment_type = local.merged_vars.environment_type
    
    # Dev environment specific settings
    kubernetes_version = "latest"  # Use latest in dev
    release_channel   = "REGULAR"
    
    # Security settings for dev
    enable_private_endpoint = false  # Allow external access in dev
    enable_private_nodes   = true
    master_ipv4_cidr_block = "172.16.0.32/28"  # Different from default to avoid conflicts
    
    # Current module features for dev
    dns_cache = true  # Enable DNS cache for better performance
    enable_l4_ilb_subsetting = false  # Can enable for better load balancing
    enable_cost_allocation = true  # Track costs
    gke_backup_agent_config = null  # Enable in production with {enabled = true}
    
    # Master authorized networks - restrict to authorized IPs
    master_authorized_networks = [
      {
        cidr_block   = "10.0.0.0/24"
        display_name = "office-network"
      },
      {
        cidr_block   = "192.168.1.0/24"
        display_name = "vpn-range"
      },
      {
        cidr_block   = "172.16.0.0/16"
        display_name = "private-network"
      },
      {
        cidr_block   = "203.0.113.0/24"
        display_name = "public-range"
      }
    ]
    
    # Node pools configuration for dev
    node_pools = [
      {
        name               = "workers-pool-00"
        initial_node_count = 0  # Start with 0 nodes for cost optimization
        machine_type       = "n2d-highcpu-2"  # Minimal setup: cost-effective high-CPU machine
        disk_size_gb       = 50
        disk_type          = "pd-standard"
        preemptible        = false
        spot               = true  # Use spot VMs for cost savings in dev
        auto_repair        = true
        auto_upgrade       = true
        # service_account is omitted - will use the cluster's created service account
        enable_gvnic       = false
        enable_fast_socket = false
        # Autoscaling configuration with total limits
        autoscaling        = true
        location_policy    = "ANY"  # Prioritize unused reservations
        total_min_count = 0
        total_max_count = 3
      }
    ]
    
    # Workload Identity configuration
    identity_namespace = "${dependency.project.outputs.project_id}.svc.id.goog"
    
    # Labels
    cluster_resource_labels = merge(
      {
        managed_by       = "terragrunt"
        component        = "gke"
        environment      = local.merged_vars.environment
        environment_type = local.merged_vars.environment_type
        cluster_name     = local.cluster_id
        module_version   = "current"
      },
      try(local.merged_vars.org_labels, {}),
      try(local.merged_vars.env_labels, {}),
      try(local.merged_vars.project_labels, {})
    )
    
    # Node pools labels
    node_pools_labels = {
      all = merge(
        {
          managed_by       = "terragrunt"
          component        = "gke"
          environment      = local.merged_vars.environment
          environment_type = local.merged_vars.environment_type
        },
        try(local.merged_vars.org_labels, {}),
        try(local.merged_vars.env_labels, {})
      )
    }
    
    # Node pools tags
    node_pools_tags = {
      all = ["gke-node", "terragrunt-managed", local.merged_vars.environment]
    }
  }
)
```

### Production Cluster Configuration

For production environments, consider these additional settings:

```hcl
inputs = merge(
  {
    # ... other configurations ...
    
    # Production security settings
    enable_private_endpoint = true  # No public access
    enable_private_nodes   = true
    enable_binary_authorization = true
    network_policy = true
    
    # Master authorized networks - restrict to authorized IPs
    master_authorized_networks = [
      {
        cidr_block   = "10.0.0.0/24"
        display_name = "office-network"
      },
      {
        cidr_block   = "192.168.1.0/24"
        display_name = "vpn-range"
      },
      {
        cidr_block   = "172.16.0.0/16"
        display_name = "private-network"
      },
      {
        cidr_block   = "203.0.113.0/24"
        display_name = "public-range"
      }
    ]
    
    # Production node pools
    node_pools = [
      {
        name               = "primary-pool"
        initial_node_count = 3
        min_count         = 3
        max_count         = 10
        machine_type      = "n2-standard-4"
        disk_size_gb      = 100
        disk_type         = "pd-ssd"
        preemptible       = false
        spot              = false
        auto_repair       = true
        auto_upgrade      = true
        service_account   = dependency.project.outputs.service_account_email
        enable_gvnic      = true  # Better network performance
        enable_fast_socket = true  # Enhanced networking
        enable_confidential_nodes = true  # Memory encryption
      }
    ]
    
    # Enable production features
    gke_backup_agent_config = { enabled = true }
    enable_cost_allocation = true
    stateful_ha = true
    monitoring_enable_managed_prometheus = true
    
    # Enhanced monitoring
    monitoring_enabled_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    logging_enabled_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER"]
  }
)
```

## Network Configuration

### VPC Requirements

#### Dedicated GKE Subnet
The recommended pattern is to use a dedicated subnet for GKE clusters:

```hcl
# In vpc-network/terragrunt.hcl - primary subnet for GKE
{
  subnet_name           = "${dependency.project.outputs.project_name}-${local.parent_folder_name}-gke"
  subnet_ip             = "10.132.64.0/18"  # 16,384 IPs for nodes
  subnet_region         = try(local.env_vars.locals.region, "europe-west2")
  subnet_private_access = true
  subnet_flow_logs      = true
  description           = "Dedicated subnet for GKE clusters"
}
```

#### Secondary Ranges
The GKE subnet must include secondary ranges for pods and services:

```hcl
# In vpc-network/terragrunt.hcl
secondary_ranges = {
  "gke-subnet" = [
    {
      range_name    = "cluster-01-pods"
      ip_cidr_range = "10.132.128.0/21"  # 2,048 IPs for pods
    },
    {
      range_name    = "cluster-01-services"
      ip_cidr_range = "10.132.192.0/24"  # 256 IPs for services
    }
  ]
}
```

### Firewall Rules

Create firewall rules for GKE master-to-webhook communication:

```hcl
# In firewall-rules/gke-master-webhooks/terragrunt.hcl
rules = [
  {
    name        = "gke-master-to-webhook"
    description = "Allow GKE master to communicate with admission webhooks"
    direction   = "INGRESS"
    priority    = 1000
    ranges      = ["172.16.0.32/28"]  # Your master CIDR
    ports = {
      tcp = ["443", "8443", "9443", "15017"]
    }
    target_tags = ["gke-node"]
    allow = [{
      protocol = "tcp"
      ports    = ["443", "8443", "9443", "15017"]
    }]
    deny = []
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
]
```

## Manual Management

Use the dedicated workflow for manual cluster management:

```bash
# Plan changes
gh workflow run manage-gke-cluster.yml \
  --field action=plan \
  --field cluster=dp-dev-01/cluster-01 \
  --field environment=development

# Apply changes
gh workflow run manage-gke-cluster.yml \
  --field action=apply \
  --field cluster=dp-dev-01/cluster-01 \
  --field environment=development

# Destroy cluster
gh workflow run manage-gke-cluster.yml \
  --field action=destroy \
  --field cluster=dp-dev-01/cluster-01 \
  --field environment=development
```

## Troubleshooting

### Common Issues

1. **Provider version error**: Ensure Google provider version meets module requirements
   ```hcl
   required_providers {
     google = {
       source  = "hashicorp/google"
       version = ">= 6.38.0"  # Check module documentation for current requirements
     }
   }
   ```

2. **DNS resolution slow**: Enable DNS cache configuration
   ```hcl
   dns_cache = true
   ```

3. **High networking costs**: Enable L4 ILB subsetting
   ```hcl
   enable_l4_ilb_subsetting = true
   ```

4. **Backup requirements**: Enable GKE backup agent
   ```hcl
   gke_backup_agent_config = { enabled = true }
   ```

5. **Cost visibility**: Enable cost allocation feature
   ```hcl
   enable_cost_allocation = true
   ```

### Authentication Issues

Ensure proper authentication for GCS state backend access:
```bash
# Set up service account authentication
export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json

# Verify authentication
gcloud auth list

# Should show tofu-sa-org@org-automation.iam.gserviceaccount.com as active
```

For terragrunt commands, use the authentication environment variable:
```bash
# Example terragrunt commands with authentication
GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json terragrunt run plan
GOOGLE_APPLICATION_CREDENTIALS=~/tofu-sa-org-key.json terragrunt run apply
```

### Secondary Range Issues

Verify secondary ranges are properly configured:
```bash
gcloud compute networks subnets describe SUBNET_NAME \
  --region=REGION \
  --project=PROJECT_ID \
  --format="get(secondaryIpRanges)"
```

## Best Practices

### Security
- **Enable private nodes and endpoints** in production
- **Use workload identity** for all workloads
- **Configure binary authorization** for image verification
- **Enable confidential nodes** where applicable
- **Restrict master authorized networks** to known IPs

### Performance
- **Enable GVNIC** for n2 instances
- **Use DNS cache** for better resolution
- **Configure fast socket** for supported workloads
- **Use storage pools** for I/O intensive workloads
- **Enable L4 ILB subsetting** for better load distribution

### Cost Optimization
- **Use spot instances** in non-production
- **Start with 0 nodes** and scale based on demand (minimal approach)
- **Use total limits** rather than per-zone limits for flexibility
- **Use location_policy = "ANY"** for better spot instance availability
- **Disable non-essential features** in development (minimal configuration)
- **Use smaller machine types** (n2d-highcpu-2) for development workloads
- **Enable cost allocation** in production for tracking

### Operations
- **Enable GKE backup agent** in production
- **Use fleet management** for multi-cluster
- **Configure proper maintenance windows**
- **Enable component-level monitoring**
- **Use managed Prometheus** for observability

## API Requirements

Ensure these APIs are enabled in your project:
- `container.googleapis.com`
- `gkebackup.googleapis.com`
- `gkehub.googleapis.com`
- `artifactregistry.googleapis.com`
- `cloudresourcemanager.googleapis.com`

## Related Documentation

- [Network Template](NETWORK_TEMPLATE.md) - VPC configuration
- [Project Template](PROJECT_TEMPLATE.md) - Project setup
- [Firewall Template](FIREWALL_TEMPLATE.md) - Security rules
- [GitHub Workflows](WORKFLOWS.md) - CI/CD automation

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review the example configurations
3. Verify all dependencies are met
4. Check GitHub Actions logs for workflow issues