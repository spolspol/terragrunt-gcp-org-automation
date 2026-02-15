# Development Infrastructure

## Overview

The development environment (`live/non-production/development/`) provides a comprehensive non-production infrastructure for development and testing. It includes three sub-environments, each demonstrating a different architectural pattern.

## Directory Structure

```
live/non-production/development/
├── env.hcl                          # Environment configuration
├── folder/                          # GCP folder for development
├── folder-iam-bindings/             # Folder-level IAM
├── dp-dev-01/                          # General-purpose project
│   ├── project.hcl
│   ├── project/
│   ├── vpc-network/                 # Multi-subnet VPC
│   ├── iam-bindings/
│   ├── iam-service-accounts/
│   ├── iam-workload-identity/
│   ├── cloud-armor/
│   ├── global/cloud-dns/
│   ├── europe-west2/
│   │   ├── compute/                 # VM instances
│   │   ├── cloud-sql/               # SQL Server + PostgreSQL
│   │   ├── cloud-run/               # Serverless services
│   │   ├── gke/                     # GKE cluster
│   │   ├── artifact-registry/
│   │   ├── certificate-manager/
│   │   ├── bigquery/
│   │   ├── buckets/
│   │   ├── networking/
│   │   └── secrets/
│   └── secrets/
├── functions/                       # Serverless (Cloud Run) pattern
│   ├── folder/
│   ├── folder-iam-bindings/
│   └── fn-dev-01/                       # Cloud Run project
│       ├── project.hcl
│       ├── project/
│       ├── vpc-network/             # Private + Serverless subnets
│       ├── iam-bindings/
│       ├── iam-service-accounts/
│       ├── artifact-registry/
│       ├── cloud-armor/
│       ├── global/cloud-dns/
│       └── europe-west2/
│           ├── cloud-run/           # webhook-handler, api-service
│           ├── cloud-sql/           # PostgreSQL
│           ├── certificate-manager/
│           ├── load-balancer/
│           ├── networking/
│           └── secrets/
└── platform/                        # Data Platform (GKE) pattern
    ├── folder/
    ├── folder-iam-bindings/
    └── dp-dev-01/                       # Data platform project
        ├── project.hcl
        ├── project/
        ├── vpc-network/             # 5-subnet VPC with GKE ranges
        ├── iam-bindings/
        ├── iam-service-accounts/
        ├── iam-workload-identity/
        ├── global/cloud-dns/
        └── europe-west2/
            ├── gke/                 # GKE cluster + ArgoCD
            ├── cloud-sql/           # PostgreSQL
            ├── bigquery/
            ├── buckets/
            ├── networking/
            └── secrets/
```

## IP Allocation

| Project | VPC CIDR | PSA Range | GKE Master |
|---------|----------|-----------|------------|
| dp-dev-01 | 10.10.0.0/16 | 10.10.200.0/24 | 172.16.0.0/28 |
| fn-dev-01 | 10.20.0.0/16 | 10.20.200.0/24 | N/A |
| dp-dev-01 | 10.30.0.0/16 | 10.30.200.0/24 | 172.16.0.48/28 |

## Sub-environment Patterns

### dp-dev-01: General Purpose

The base project with examples of all resource types. VPC has 5 subnets:
- **DMZ** (10.10.0.0/21) - Bastion hosts, public-facing services
- **Private** (10.10.8.0/21) - Internal services, databases
- **Public** (10.10.16.0/21) - Services requiring NAT
- **GKE** (10.10.64.0/20) - GKE nodes with pod/service secondary ranges
- **Serverless** (10.10.96.0/23) - Cloud Run VPC connector

### fn-dev-01: Serverless Functions

Demonstrates the Cloud Run serverless pattern:
- External Application Load Balancer with path-based routing
- Cloud Armor WAF for IP allowlisting
- Certificate Manager for TLS via private CA
- Cloud SQL PostgreSQL via Private Service Access
- Artifact Registry as GHCR remote proxy
- Service accounts: `cr-deployer` (CI/CD) and `cr-runner` (runtime)

### dp-dev-01: Data Platform

Demonstrates the GKE + data engineering pattern:
- Private GKE cluster with ArgoCD GitOps bootstrap
- Workload Identity bindings for Kubernetes service accounts
- Cloud SQL PostgreSQL for application state
- BigQuery datasets for data warehouse
- Cloud Storage for compute logs
- DNS peering to hub for centralised resolution

## Environment Settings

```hcl
# env.hcl
environment          = "development"
environment_type     = "non-production"
gke_security_group   = "gke-security-groups@example.com"
forward_domain       = "dev.example.io"
deletion_protection  = false
monitoring_level     = "standard"
backup_retention     = "7d"
```

## Deployment Order

Resources must be deployed in dependency order:

1. **Folder** - Creates the development GCP folder
2. **Folder IAM Bindings** - Sets folder-level permissions
3. **Sub-folders** (functions/folder, platform/folder)
4. **Projects** (dp-dev-01, fn-dev-01, dp-dev-01)
5. **VPC Networks** - Creates subnets and secondary ranges
6. **Private Service Access** - Enables managed service connectivity
7. **Networking** (Cloud Router, NAT, External IPs, Firewall Rules)
8. **IAM** (Project bindings, Service Accounts, Workload Identity)
9. **Resources** (GKE, Cloud SQL, Cloud Run, BigQuery, etc.)
10. **Secrets** - Create placeholders, populate manually
11. **DNS** - Zones and records (after resources provide IPs)

## Related Documentation

- [Network Architecture](./NETWORK_ARCHITECTURE.md)
- [GKE Template](./GKE_TEMPLATE.md)
- [Cloud Run Template](./CLOUD_RUN_TEMPLATE.md)
- [Cloud SQL PostgreSQL Template](./CLOUD_SQL_POSTGRES_TEMPLATE.md)
- [IP Allocation](./IP_ALLOCATION.md)
