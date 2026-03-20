# GKE Template

Deploys private GKE clusters using the `terraform-google-kubernetes-engine` module (v41.0.2). The template handles cluster creation, node pool configuration, NAT gateway integration, and Workload Identity setup.

## Overview

| Property | Value |
|----------|-------|
| Template | `_common/templates/gke.hcl` |
| Module | `terraform-google-kubernetes-engine` |
| Version | Defined in `_common/common.hcl` as `gke` |
| Example cluster | `live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01/` |

Clusters are always private (nodes use internal IPs). Internet access for image pulls and API calls is routed through a shared NAT gateway in the same VPC.

## Configuration

### Cluster Naming

Clusters follow the pattern `{project}-{region-abbr}-{cluster-id}`. The region abbreviation uses the first letter of each segment plus the last character (e.g., `europe-west2` becomes `ew2`):

```hcl
locals {
  project_name = try(dependency.project.outputs.project_name, "dp-dev-01")
  cluster_name = "${local.project_name}-ew2-cluster-01"
}
```

### Key Parameters

| Parameter | Dev | Prod | Notes |
|-----------|-----|------|-------|
| `enable_private_nodes` | `true` | `true` | Always private |
| `enable_private_endpoint` | `true` | `true` | VPN-only access (dp-dev-01) |
| `release_channel` | `RAPID` | `STABLE` | Controls upgrade cadence |
| `spot` | `true` | `false` | Cost savings in non-prod |
| `enable_shielded_nodes` | `true` | `true` | Secure boot |
| `monitoring_enable_managed_prometheus` | `true` | `true` | Metrics collection |
| `maintenance_start_time` | `"01:00"` | `"01:00"` | Daily window, UTC |

### Node Pools

The development cluster uses two pools:

```hcl
node_pools = [
  {
    name               = "system-pool-00"
    machine_type       = "e2-standard-2"
    min_count          = 1
    max_count          = 3
    disk_size_gb       = 50
    disk_type          = "pd-standard"
    spot               = true
    initial_node_count = 1
  },
  {
    name               = "workload-pool-00"
    machine_type       = "e2-standard-4"
    min_count          = 0
    max_count          = 5
    disk_size_gb       = 100
    disk_type          = "pd-standard"
    spot               = true
    initial_node_count = 0
  },
]
```

For production, use on-demand instances (`spot = false`), larger machines (`n2-standard-4`), SSD disks, and enable `enable_gvnic` and `enable_fast_socket` for better network throughput.

## Usage

Create a cluster directory and a `terragrunt.hcl` that includes the template:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "gke_template" {
  path           = "${get_repo_root()}/_common/templates/gke.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_name      = "mock-network"
    network_self_link = "projects/mock-project/global/networks/mock-network"
    subnets_names     = ["mock-network-gke"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  project_id = dependency.project.outputs.project_id
  name       = "${dependency.project.outputs.project_name}-ew2-cluster-01"
  region     = include.base.locals.region

  network    = dependency.network.outputs.network_name
  subnetwork = "${dependency.network.outputs.network_name}-gke"

  ip_range_pods     = "cluster-01-pods"
  ip_range_services = "cluster-01-services"

  enable_private_nodes    = true
  enable_private_endpoint = true
  master_ipv4_cidr_block  = "172.16.0.48/28"

  node_pools = [
    {
      name         = "system-pool-00"
      machine_type = "e2-standard-2"
      min_count    = 1
      max_count    = 3
      spot         = true
    },
  ]
}
```

### Connecting to the Cluster

```bash
gcloud container clusters get-credentials dp-dev-01-ew2-cluster-01 \
  --region europe-west2 \
  --project <PROJECT_ID> \
  --internal-ip  # required for private-endpoint clusters
```

## Directory Structure

```
live/non-production/development/platform/dp-dev-01/
└── europe-west2/
    └── gke/
        └── cluster-01/
            ├── terragrunt.hcl          # Cluster config
            └── bootstrap-argocd/
                └── terragrunt.hcl      # ArgoCD install
```

## Dependencies

The GKE cluster depends on:

1. **Project** -- must exist with `container.googleapis.com` API enabled
2. **VPC network** -- with a dedicated GKE subnet and secondary ranges for pods/services
3. **NAT gateway external IP** -- used in master authorized networks
4. **Private Service Access** -- if connecting to Cloud SQL or other private services

Secondary IP ranges must be pre-configured on the GKE subnet:

```hcl
secondary_ranges = {
  "network-gke" = [
    { range_name = "cluster-01-pods",     ip_cidr_range = "10.132.128.0/21" },
    { range_name = "cluster-01-services", ip_cidr_range = "10.132.192.0/24" },
  ]
}
```

## Troubleshooting

1. **"master_ipv4_cidr_block conflicts"** -- each cluster needs a unique /28 CIDR for the control plane. Check existing allocations before assigning.

2. **Nodes cannot pull images** -- verify the NAT gateway is deployed in the same VPC and that node tags include `nat-enabled` or equivalent target tags in the Cloud NAT config.

3. **`kubectl` connection refused** -- for private-endpoint clusters, you must connect through VPN or a bastion. Pass `--internal-ip` to `gcloud container clusters get-credentials`.

4. **Webhook admission errors** -- create a firewall rule allowing the master CIDR (e.g., `172.16.0.48/28`) to reach node ports `443`, `8443`, `9443`, `15017` with target tag `gke-node`.

5. **Secondary range not found** -- ensure the VPC subnet has secondary ranges named exactly as referenced by `ip_range_pods` and `ip_range_services`.

## References

- [GKE Module](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine)
- [Network Template](NETWORK_TEMPLATE.md)
- [Project Template](PROJECT_TEMPLATE.md)

- [GitOps Architecture](GITOPS_ARCHITECTURE.md)
