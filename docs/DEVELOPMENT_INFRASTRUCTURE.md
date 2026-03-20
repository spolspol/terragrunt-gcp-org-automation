# Development Infrastructure

The development environment (`live/non-production/development/`) hosts two sub-environments that demonstrate distinct architectural patterns:

- **platform/dp-dev-01** -- fully private infrastructure accessed exclusively via VPN. Runs GKE with ArgoCD, Cloud SQL, BigQuery, and compute instances behind a deny-all-ingress firewall. All traffic routes through the hub VPN gateway.
- **functions/fn-dev-01** -- serverless architecture with a public-facing External Application Load Balancer. Cloud Run services sit behind Cloud Armor WAF and TLS termination, with PostgreSQL and secrets on private networking.

## Directory Structure

```
live/non-production/development/
├── env.hcl                              # Environment configuration
├── folder/                              # GCP folder for development
├── folder-iam-bindings/                 # Folder-level IAM
├── functions/                           # Serverless (Cloud Run) pattern
│   ├── folder/
│   ├── folder-iam-bindings/
│   └── fn-dev-01/
│       ├── project.hcl
│       ├── project/
│       ├── vpc-network/                 # Private + Serverless subnets
│       ├── iam-bindings/
│       ├── iam-service-accounts/
│       ├── artifact-registry/
│       ├── cloud-armor/
│       ├── global/cloud-dns/
│       └── europe-west2/
│           ├── cloud-run/               # webhook-handler, api-service
│           ├── cloud-sql/               # PostgreSQL
│           ├── certificate-manager/
│           ├── load-balancer/
│           ├── networking/
│           └── secrets/
└── platform/                            # Data Platform (GKE) pattern
    ├── folder/
    ├── folder-iam-bindings/
    └── dp-dev-01/
        ├── project.hcl
        ├── project/
        ├── vpc-network/                 # 5-subnet VPC with GKE ranges
        ├── iam-bindings/
        ├── iam-service-accounts/
        ├── iam-workload-identity/
        ├── cloud-armor/
        ├── global/cloud-dns/
        └── europe-west2/
            ├── gke/                     # GKE cluster + ArgoCD bootstrap
            ├── compute/                 # VM instances
            ├── cloud-sql/               # SQL Server + PostgreSQL
            ├── cloud-run/               # Serverless services
            ├── artifact-registry/
            ├── certificate-manager/
            ├── bigquery/
            ├── buckets/
            ├── networking/
            └── secrets/
```

## IP Allocation

| Project | Path | VPC CIDR | PSA Range | GKE Master |
|---------|------|----------|-----------|------------|
| dp-dev-01 | `platform/dp-dev-01/` | 10.30.0.0/16 | 10.30.200.0/24 | 172.16.0.48/28 |
| fn-dev-01 | `functions/fn-dev-01/` | 10.20.0.0/16 | 10.20.200.0/24 | N/A |

## Sub-environment Patterns

### platform/dp-dev-01 -- Data Platform (private, VPN-only)

Fully private infrastructure accessible only via the hub VPN gateway.

- **VPC**: 5 subnets -- DMZ, Private, Public (NAT), GKE nodes (with pod/service secondary ranges), Serverless (VPC connector)
- **GKE**: Private cluster with ArgoCD GitOps bootstrap
- **Workload Identity**: Kubernetes service account to GCP IAM bindings
- **Cloud SQL**: PostgreSQL for application state
- **BigQuery**: Datasets for data warehouse
- **Cloud Storage**: Compute logs
- **DNS**: Peering to hub for centralised resolution

### functions/fn-dev-01 -- Serverless Functions (public LB)

Public-facing serverless pattern with managed security at the edge.

- **Load Balancer**: External Application LB with path-based routing
- **Cloud Armor**: WAF for IP allowlisting and DDoS protection
- **Certificate Manager**: TLS via private CA
- **Cloud Run**: `webhook-handler` and `api-service` containers
- **Cloud SQL**: PostgreSQL via Private Service Access
- **Artifact Registry**: GHCR remote proxy
- **Service Accounts**: `cr-deployer` (CI/CD) and `cr-runner` (runtime)

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

1. **Folder** -- development GCP folder
2. **Folder IAM Bindings** -- folder-level permissions
3. **Sub-folders** (functions/folder, platform/folder)
4. **Projects** (dp-dev-01, fn-dev-01)
5. **VPC Networks** -- subnets and secondary ranges
6. **Private Service Access** -- managed service connectivity
7. **Networking** (Cloud Router, NAT, External IPs, Firewall Rules)
8. **IAM** (Project bindings, Service Accounts, Workload Identity)
9. **Resources** (GKE, Cloud SQL, Cloud Run, BigQuery, Buckets)
10. **Secrets** -- create placeholders, populate manually
11. **DNS** -- zones and records (after resources provide IPs)

## Related Documentation

- [Network Architecture](./NETWORK_ARCHITECTURE.md)
- [GKE Template](./GKE_TEMPLATE.md)
- [Cloud Run Template](./CLOUD_RUN_TEMPLATE.md)
- [Cloud SQL PostgreSQL Template](./CLOUD_SQL_POSTGRES_TEMPLATE.md)
- [IP Allocation](./IP_ALLOCATION.md)
