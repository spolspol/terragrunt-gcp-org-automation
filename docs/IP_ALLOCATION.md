# IP Allocation Documentation

This document describes the IP allocation strategy and management for the GCP infrastructure managed through Terragrunt.

> **Note**: The canonical IP allocations are maintained in `ip-allocation.yaml`. The current active project ranges are: vpn-gateway `10.11.0.0/16`, fn-dev-01 `10.20.0.0/16`, dp-dev-01 `10.30.0.0/16`. Some sections below still reference the legacy development block scheme (10.128.0.0/10) -- refer to `ip-allocation.yaml` and the README table for authoritative values.

## Overview

The infrastructure uses a hierarchical IP allocation scheme designed to support multiple environments, prevent IP conflicts, and allow for significant growth.

### Total Managed IP Space

```mermaid
pie title "IP Address Distribution (25M Total)"
    "Development" : 4.2
    "Perimeter" : 4.2
    "Production" : 16.7
```

- **Development Block**: 10.128.0.0/10 (4.2M IPs)
- **Perimeter Block**: 10.192.0.0/10 (4.2M IPs)
- **Production Block**: 10.0.0.0/8 (16.7M IPs)
- **Total**: ~25M IP addresses

## IP Allocation Strategy

### Hierarchical Structure

```mermaid
flowchart TB
    subgraph "IP Allocation Hierarchy"
        ORG("<b>Organization<br/>25M IPs Total</b>")

        subgraph BLOCKS["Major Blocks"]
            DEV("<b>Development<br/>10.128.0.0/10<br/>4.2M IPs</b>")
            PERIM("<b>Perimeter<br/>10.192.0.0/10<br/>4.2M IPs</b>")
            PROD("<b>Production<br/>10.0.0.0/8<br/>16.7M IPs</b>")
        end

        subgraph ENVS["Environments (/16 each)"]
            DEV01("<b>dp-dev-01<br/>10.30.0.0/16<br/>65,536 IPs</b>")
            FNDEV01("<b>fn-dev-01<br/>10.20.0.0/16</b>")
            VPNGW("<b>vpn-gateway<br/>10.11.0.0/16</b>")
        end

        subgraph SUBNETS["Subnet Types"]
            DMZ("<b>DMZ /21<br/>2,048 IPs</b>")
            PRIV("<b>Private /21<br/>2,048 IPs</b>")
            PUB("<b>Public /21<br/>2,048 IPs</b>")
            GKE("<b>GKE /18<br/>16,384 IPs</b>")
        end
    end

    ORG --> BLOCKS
    DEV --> ENVS
    DEV01 --> SUBNETS

    classDef hub fill:#ffe0b2,stroke:#e65100,stroke-width:3px,color:#000
    classDef network fill:#b3e5fc,stroke:#0277bd,stroke-width:3px,color:#000
    classDef compute fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,color:#000
    classDef security fill:#f8bbd0,stroke:#c2185b,stroke-width:3px,color:#000
    classDef storage fill:#e1bee7,stroke:#7b1fa2,stroke-width:3px,color:#000

    class ORG hub
    class BLOCKS,DEV,PERIM,PROD network
    class ENVS,DEV01,FNDEV01,VPNGW compute
    class SUBNETS,DMZ,PRIV,PUB,GKE storage

    linkStyle 0,1,2 stroke:#2e7d32,stroke-width:2px
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

```mermaid
flowchart LR
    subgraph "Active Projects"
        VPNGW("<b>vpn-gateway<br/>10.11.0.0/16</b>")
        FNDEV("<b>fn-dev-01<br/>10.20.0.0/16</b>")
        DPDEV("<b>dp-dev-01<br/>10.30.0.0/16</b>")
    end

    subgraph "Available"
        AVAIL("<b>Additional /16 blocks<br/>available for new projects</b>")
    end

    classDef hub fill:#ffe0b2,stroke:#e65100,stroke-width:3px,color:#000
    classDef compute fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,color:#000
    classDef network fill:#b3e5fc,stroke:#0277bd,stroke-width:3px,color:#000

    class VPNGW hub
    class FNDEV,DPDEV compute
    class AVAIL network
```

See `ip-allocation.yaml` for current per-project subnet breakdowns. Active project blocks:

| Project | Block | Status |
|---------|-------|--------|
| vpn-gateway | 10.11.0.0/16 | Active |
| fn-dev-01 | 10.20.0.0/16 | Active |
| dp-dev-01 | 10.30.0.0/16 | Active |

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

```mermaid
flowchart TB
    subgraph "CIDR Boundary Alignment Rules"
        subgraph "/21 Blocks"
            A21("<b>Third octet / 8 = integer<br/>Valid: 10.x.0.0/21, 10.x.8.0/21<br/>Invalid: 10.x.4.0/21</b>")
        end

        subgraph "/18 Blocks"
            A18("<b>Third octet / 64 = integer<br/>Valid: 10.x.64.0/18, 10.x.128.0/18<br/>Invalid: 10.x.32.0/18</b>")
        end

        subgraph "/19 Blocks"
            A19("<b>Third octet / 32 = integer<br/>Valid: 10.x.32.0/19, 10.x.160.0/19<br/>Invalid: 10.x.48.0/19</b>")
        end

        subgraph "/24 Blocks"
            A24("<b>Always aligned<br/>Any x.x.x.0/24</b>")
        end
    end

    classDef network fill:#b3e5fc,stroke:#0277bd,stroke-width:3px,color:#000

    class A21,A18,A19,A24 network
```

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
    dp-dev-01:
      block: "10.132.0.0/16"
      primary_subnets:
        dmz:
          cidr: "10.132.0.0/21"
```

### Validation Tools

#### IP Allocation Checker

```mermaid
flowchart LR
    subgraph COMMANDS["Available Commands"]
        VALIDATE("<b>validate<br/>Check conflicts</b>")
        VISUALIZE("<b>visualize<br/>Show allocations</b>")
        AVAIL("<b>available<br/>List free blocks</b>")
        NEXT("<b>next<br/>Suggest allocation</b>")
    end

    subgraph OUTPUTS["Output Types"]
        REPORT("<b>Validation Report</b>")
        DIAGRAM("<b>Visual Map</b>")
        LIST("<b>Available Ranges</b>")
        SUGGEST("<b>Next Assignment</b>")
    end

    VALIDATE --> REPORT
    VISUALIZE --> DIAGRAM
    AVAIL --> LIST
    NEXT --> SUGGEST

    classDef network fill:#b3e5fc,stroke:#0277bd,stroke-width:3px,color:#000
    classDef hub fill:#ffe0b2,stroke:#e65100,stroke-width:3px,color:#000

    class VALIDATE,VISUALIZE,AVAIL,NEXT network
    class REPORT,DIAGRAM,LIST,SUGGEST hub

    linkStyle 0,1,2,3 stroke:#2e7d32,stroke-width:2px
```

The `scripts/ip-allocation-checker.py` tool provides:

```bash
# Validate all allocations for conflicts
python3 ip-allocation-checker.py validate

# Visualize current allocations
python3 ip-allocation-checker.py visualize

# Show available blocks
python3 ip-allocation-checker.py available

# Suggest next cluster allocation
python3 ip-allocation-checker.py next dp-dev-01
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

```mermaid
flowchart TB
    subgraph DEV["Development"]
        DACT("<b>Active: 1</b>")
        DRES("<b>Reserved: 3</b>")
        DAVL("<b>Available: 60</b>")
    end

    subgraph PERIM["Perimeter"]
        PACT("<b>Active: 0</b>")
        PRES("<b>Reserved: 2</b>")
        PAVL("<b>Available: 62</b>")
    end

    subgraph PROD["Production"]
        PRACT("<b>Active: 0</b>")
        PRRES("<b>Reserved: 2</b>")
        PRAVL("<b>Available: 254</b>")
    end

    classDef compute fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,color:#000
    classDef hub fill:#ffe0b2,stroke:#e65100,stroke-width:3px,color:#000
    classDef network fill:#b3e5fc,stroke:#0277bd,stroke-width:3px,color:#000

    class DACT,PACT,PRACT compute
    class DRES,PRES,PRRES hub
    class DAVL,PAVL,PRAVL network
```

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

#### GKE Clusters (dp-dev-01)
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

```mermaid
flowchart LR
    REQ("<b>1. Identify<br/>Requirement</b>")
    CHECK("<b>2. Check<br/>Available</b>")
    UPDATE("<b>3. Update<br/>YAML</b>")
    VALIDATE("<b>4. Run<br/>Validation</b>")
    CONFIG("<b>5. Update<br/>Terragrunt</b>")
    APPLY("<b>6. Apply<br/>Changes</b>")
    DOC("<b>7. Document<br/>Changelog</b>")

    REQ --> CHECK --> UPDATE --> VALIDATE --> CONFIG --> APPLY --> DOC

    classDef network fill:#b3e5fc,stroke:#0277bd,stroke-width:3px,color:#000

    class REQ,CHECK,UPDATE,VALIDATE,CONFIG,APPLY,DOC network

    linkStyle 0,1,2,3,4,5 stroke:#2e7d32,stroke-width:2px
```

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

### IP Categories

```mermaid
flowchart TB
    subgraph NAT["NAT Gateway IPs"]
        NAT1("<b>dp-dev-01-nat<br/>35.246.0.1</b>")
    end

    subgraph CLUSTER["Cluster Service IPs"]
        CL1("<b>cluster-01<br/>35.246.0.123</b>")
        CL2("<b>cluster-02<br/>Reserved</b>")
    end

    subgraph SQL["SQL Server IPs"]
        SQL1("<b>sql-server-01<br/>35.246.0.200</b>")
    end

    classDef compute fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,color:#000
    classDef hub fill:#ffe0b2,stroke:#e65100,stroke-width:3px,color:#000

    class NAT1,CL1,SQL1 compute
    class CL2 hub
```

### NAT Gateway IPs

External IPs for NAT gateways are managed separately:

```yaml
external_ips:
  nat_gateways:
    - name: "dp-dev-01-nat-gateway"
      ip: "35.246.0.1"
      region: "europe-west2"
```

### Cluster Service IPs

Each GKE cluster requires external IPs for ingress:

```yaml
cluster_services:
  - name: "dp-dev-01-cluster-01-services"
    ip: "35.246.0.123"
    purpose: "Ingress controller"
```

### SQL Server IPs

Database servers may require external IPs:

```yaml
sql_servers:
  - name: "dp-dev-01-sql-server-01"
    ip: "35.246.0.200"
    purpose: "SQL Server access"
```

## References

- [ip-allocation.yaml](../ip-allocation.yaml) - Central tracking file
- [IP Allocation Checker](../scripts/ip-allocation-checker.py) - Validation tool
- [Network Architecture](NETWORK_ARCHITECTURE.md) - Network design documentation
- [GCP VPC Documentation](https://cloud.google.com/vpc/docs) - Google Cloud VPC guide
