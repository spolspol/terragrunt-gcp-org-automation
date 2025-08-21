# IP Allocation Documentation

This document describes the IP allocation strategy and management for the GCP infrastructure managed through Terragrunt.

## Table of Contents

- [Overview](#overview)
- [IP Allocation Strategy](#ip-allocation-strategy)
- [Network Blocks](#network-blocks)
- [Environment Allocations](#environment-allocations)
- [CIDR Alignment Rules](#cidr-alignment-rules)
- [Tracking and Validation](#tracking-and-validation)
- [Future Planning](#future-planning)

## Overview

The infrastructure uses a hierarchical IP allocation scheme designed to:
- Support multiple environments (development, perimeter, production)
- Enable clear organizational structure
- Provide efficient address space utilization
- Allow for significant growth
- Prevent IP conflicts across environments

### Total Managed IP Space

- **Development Block**: 10.128.0.0/10 (4.2M IPs)
- **Perimeter Block**: 10.192.0.0/10 (4.2M IPs)
- **Production Block**: 10.0.0.0/8 (16.7M IPs)
- **Total**: ~25M IP addresses

## IP Allocation Strategy

### Hierarchical Structure

```
Organization (10.0.0.0/8 + 10.128.0.0/10)
├── Development (10.128.0.0/10)
│   ├── dev-01 (10.132.0.0/16)
│   ├── dev-02 (10.133.0.0/16)
│   └── ... (up to 64 environments)
├── Perimeter (10.192.0.0/10)
│   ├── data-staging (10.196.0.0/16)
│   └── dns-infra (10.197.0.0/16)
└── Production (10.0.0.0/8)
    ├── prod-01 (10.4.0.0/16)
    └── prod-02 (10.5.0.0/16)
```

### Per-Environment Allocation

Each environment receives a /16 block (65,536 IPs) subdivided as:

| Subnet Type | CIDR Range | Size | Purpose |
|------------|------------|------|---------|
| DMZ | x.x.0.0/21 | 2,048 IPs | Controlled external access |
| Private | x.x.8.0/21 | 2,048 IPs | Internal resources |
| Public | x.x.16.0/21 | 2,048 IPs | Internet-facing resources |
| GKE | x.x.64.0/18 | 16,384 IPs | Kubernetes clusters |
| Reserved | x.x.24.0/13 | 8,192 IPs | Future expansion |

### GKE Secondary Ranges

Each GKE cluster requires secondary ranges for pods and services:

| Range Type | CIDR | Size | Supports |
|------------|------|------|----------|
| Pods | /21 | 2,048 IPs | ~250 nodes with 8 pods each |
| Services | /24 | 256 IPs | 256 Kubernetes services |

## Network Blocks

### Development Block Details

**Block**: 10.128.0.0/10  
**Range**: 10.128.0.0 - 10.191.255.255  
**Capacity**: 64 environments × 65,536 IPs

#### Active Environments

**dev-01**: 10.132.0.0/16
- Status: Active
- Utilization: 51.6% (33,792 IPs allocated)
- Available: 48.4% (31,744 IPs)

```yaml
Primary Subnets:
  dmz:     10.132.0.0/21  (2,048 IPs)
  private: 10.132.8.0/21   (2,048 IPs)
  public:  10.132.16.0/21  (2,048 IPs)
  gke:     10.132.64.0/18  (16,384 IPs)

Secondary Ranges:
  cluster-01-pods:     10.132.128.0/21 (2,048 IPs)
  cluster-01-services: 10.132.192.0/24 (256 IPs)
  cluster-02-pods:     10.132.136.0/21 (reserved)
  cluster-02-services: 10.132.193.0/24 (reserved)
```

### Perimeter Block Details

**Block**: 10.192.0.0/10  
**Range**: 10.192.0.0 - 10.255.255.255  
**Purpose**: DMZ and shared infrastructure services

### Production Block Details

**Block**: 10.0.0.0/8  
**Range**: 10.0.0.0 - 10.255.255.255  
**Status**: Reserved for future production use

## CIDR Alignment Rules

### Critical Alignment Requirements

Proper CIDR alignment is essential for valid network configuration:

1. **/21 blocks** must start at addresses divisible by 8
   - Valid: 10.132.0.0/21, 10.132.8.0/21, 10.132.16.0/21
   - Invalid: 10.132.4.0/21, 10.132.12.0/21

2. **/18 blocks** must start at addresses divisible by 64
   - Valid: 10.132.64.0/18, 10.132.128.0/18
   - Invalid: 10.132.32.0/18, 10.132.96.0/18

3. **/19 blocks** must start at addresses divisible by 32
   - Valid: 10.132.32.0/19, 10.132.160.0/19
   - Invalid: 10.132.48.0/19, 10.132.80.0/19

4. **/24 blocks** are naturally aligned (divisible by 1)

### Validation

Use the IP allocation checker to validate alignments:

```bash
cd scripts
python3 ip-allocation-checker.py validate
```

## Tracking and Validation

### Central Tracking File

All IP allocations are tracked in `ip-allocation.yaml`:

```yaml
metadata:
  schema_version: "1.1"
  last_updated: "2025-08-20"
  
development:
  block: "10.128.0.0/10"
  environments:
    dev-01:
      block: "10.132.0.0/16"
      primary_subnets:
        dmz:
          cidr: "10.132.0.0/21"
```

### Validation Tools

#### IP Allocation Checker

The `scripts/ip-allocation-checker.py` tool provides:

```bash
# Validate all allocations for conflicts
python3 ip-allocation-checker.py validate

# Visualize current allocations
python3 ip-allocation-checker.py visualize

# Show available blocks
python3 ip-allocation-checker.py available

# Suggest next cluster allocation
python3 ip-allocation-checker.py next dev-01
```

#### Automated Validation

CI/CD pipelines should include IP validation:

```yaml
- name: Validate IP Allocations
  run: |
    cd scripts
    python3 ip-allocation-checker.py validate
```

### Manual Verification

To manually verify an allocation:

1. Check the allocation doesn't overlap with existing ranges
2. Verify CIDR boundary alignment
3. Ensure sufficient space for growth
4. Update ip-allocation.yaml
5. Run validation script

## Future Planning

### Capacity Planning

Current capacity and growth potential:

| Environment Type | Total Capacity | Active | Reserved | Available |
|-----------------|---------------|---------|----------|-----------|
| Development | 64 environments | 1 | 3 | 60 |
| Perimeter | 64 environments | 0 | 2 | 62 |
| Production | 256 environments | 0 | 2 | 254 |

### Next Available Allocations

#### Development Environments
- dev-05: 10.136.0.0/16
- dev-06: 10.137.0.0/16
- dev-07: 10.138.0.0/16

#### GKE Clusters (dev-01)
- cluster-02: Already reserved
- cluster-03: Already reserved
- cluster-04: Already reserved

### Growth Strategies

1. **Vertical Scaling**: Each environment can support 4-8 GKE clusters
2. **Horizontal Scaling**: 60+ development environments available
3. **Subnet Expansion**: Reserved ranges allow doubling subnet sizes
4. **Production Migration**: Full /8 block reserved for production

## Best Practices

### Allocation Guidelines

1. **Reserve Early**: Pre-allocate ranges for planned growth
2. **Document Everything**: Update ip-allocation.yaml immediately
3. **Use Standard Sizes**: Stick to predefined subnet sizes
4. **Maintain Consistency**: Follow naming conventions
5. **Validate Changes**: Run checker before applying changes

### Naming Conventions

```
Primary Subnets:  {project}-{environment}-{type}
Secondary Ranges: {cluster-id}-{pods|services}
External IPs:     {project}-{resource}-{purpose}
```

### Change Process

1. Identify requirement
2. Check available ranges
3. Update ip-allocation.yaml
4. Run validation script
5. Update Terragrunt configurations
6. Apply changes
7. Document in changelog

## Troubleshooting

### Common Issues

#### CIDR Boundary Misalignment

**Error**: "Invalid CIDR boundary - /21 not aligned"

**Solution**: Ensure third octet is divisible by 8 for /21 blocks

#### IP Conflicts

**Error**: "IP conflict detected between subnets"

**Solution**: 
1. Run `python3 ip-allocation-checker.py visualize`
2. Identify overlapping ranges
3. Adjust allocation to next available block

#### Insufficient IPs

**Error**: "Not enough IPs in subnet"

**Solution**:
1. Check utilization with visualization tool
2. Consider using reserved expansion space
3. Evaluate if larger initial allocation needed

## External IP Management

### NAT Gateway IPs

External IPs for NAT gateways are managed separately:

```yaml
external_ips:
  nat_gateways:
    - name: "dev-01-nat-gateway"
      ip: "35.246.0.1"
      region: "europe-west2"
```

### Cluster Service IPs

Each GKE cluster requires external IPs for ingress:

```yaml
cluster_services:
  - name: "dev-01-cluster-01-services"
    ip: "35.246.0.123"
    purpose: "Ingress controller"
```

### SQL Server IPs

Database servers may require external IPs:

```yaml
sql_servers:
  - name: "dev-01-sql-server-01"
    ip: "35.246.0.200"
    purpose: "SQL Server access"
```

## References

- [ip-allocation.yaml](../ip-allocation.yaml) - Central tracking file
- [IP Allocation Checker](../scripts/ip-allocation-checker.py) - Validation tool
- [Network Architecture](NETWORK_ARCHITECTURE.md) - Network design documentation
- [GCP VPC Documentation](https://cloud.google.com/vpc/docs) - Google Cloud VPC guide