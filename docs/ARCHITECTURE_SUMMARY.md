# Infrastructure Architecture: Principles and Design Rationale

## Executive Summary

This document outlines the architectural principles and design rationale behind the organization's GCP infrastructure. Our architecture leverages OpenTofu (an open-source Terraform fork), Terragrunt for configuration management, and Google Cloud Platform for hosting. The design emphasizes security, scalability, operational excellence, and cost optimization while maintaining flexibility for future growth.

### Key Design Principles
- **Infrastructure as Code (IaC)** with version control and peer review
- **Hierarchical configuration** with inheritance and overrides
- **Separation of concerns** between infrastructure layers
- **Security by default** with least privilege access
- **Operational excellence** through automation and standardization

### Technology Stack
- **OpenTofu 1.9.1**: Infrastructure provisioning engine
- **Terragrunt 0.80.2**: Configuration management and orchestration
- **Google Cloud Platform**: Cloud infrastructure provider
- **GitHub Actions**: CI/CD automation
- **ArgoCD 8.1.3**: GitOps continuous delivery platform
- **Google Secret Manager**: Secrets management
- **External Secrets Operator**: Kubernetes secrets synchronization

## Tool Selection Rationale

### Why OpenTofu?

OpenTofu was chosen over Terraform for several strategic reasons:

1. **Open Governance**: As a Linux Foundation project, OpenTofu ensures long-term stability without vendor lock-in
2. **Community-Driven**: Development priorities are set by the community, not commercial interests
3. **License Stability**: Immune to licensing changes that could impact enterprise usage
4. **Terraform Compatibility**: Maintains full compatibility with existing Terraform configurations
5. **Future-Proof**: Protects against potential commercial restrictions or pricing changes

### Why Terragrunt?

Terragrunt provides essential capabilities for managing infrastructure at scale:

1. **DRY Principle**: Eliminates configuration duplication through templates and inheritance
2. **Hierarchical Configuration**: Natural representation of organizational structure
3. **Dependency Management**: Explicit declaration and resolution of resource dependencies
4. **State Management**: Automated remote state configuration with locking
5. **Bulk Operations**: Execute commands across multiple modules efficiently

### Why Google Cloud Platform?

GCP was selected based on:

1. **Enterprise Security**: Comprehensive security features and compliance certifications
2. **Global Infrastructure**: Presence in required regions with low latency
3. **Managed Services**: Rich ecosystem of managed services reducing operational overhead
4. **Cost Efficiency**: Competitive pricing with sustained use discounts
5. **Innovation**: Access to cutting-edge services and features

### Dynamic Configuration Patterns
All configurations now use Terragrunt directory functions for path resolution:

```hcl
locals {
  # Dynamic path construction replaces hardcoded paths
  project_base_path = dirname(dirname(get_terragrunt_dir()))
  secrets_base_path = "${local.project_base_path}/secrets"
  networking_base_path = "${dirname(get_terragrunt_dir())}/networking"
  
  # Resource name extraction from directory structure
  resource_name = basename(get_terragrunt_dir())
}

dependency "project" {
  config_path = find_in_parent_folders("project")
}
```

This pattern eliminates hardcoded relative paths and enables portable, maintainable configurations.

## Core Architectural Principles

### 1. Hierarchical Configuration Management

The infrastructure follows a strict hierarchy that mirrors organizational structure:

```
root.hcl                    # Global settings, state backend
├── account.hcl            # Account-level configuration
├── env.hcl               # Environment-specific settings
├── project.hcl           # Project configuration
└── region.hcl           # Regional settings
```

**Rationale**: This hierarchy enables:
- Configuration inheritance with selective overrides
- Clear separation between global and local settings
- Simplified multi-environment management
- Reduced configuration duplication

### 2. Don't Repeat Yourself (DRY)

All reusable configurations are centralized:

- **Templates** in `_common/templates/` for resource patterns
- **Module versions** in `_common/common.hcl` for consistency
- **Shared variables** inherited through the hierarchy

**Rationale**: 
- Single source of truth for configurations
- Simplified updates and maintenance
- Reduced human error
- Consistent resource provisioning

### 3. Separation of Concerns

Clear boundaries between:
- **Infrastructure layers** (network, compute, data)
- **Environments** (dev, staging, production)
- **Security contexts** (DMZ, internal)
- **Operational concerns** (provisioning, configuration, secrets)

**Rationale**:
- Independent evolution of components
- Blast radius limitation
- Clear ownership boundaries
- Simplified troubleshooting

### 4. Environment Parity with Flexibility

All environments follow the same patterns but with appropriate variations:

```hcl
# Production
machine_type = "n2-standard-8"
disk_size_gb = 100
preemptible = false

# Development
machine_type = "n2-standard-2"
disk_size_gb = 20
preemptible = true
```

**Rationale**:
- Consistent behavior across environments
- Cost optimization for non-production
- Production-like testing environments
- Easy promotion between environments

### 5. Security by Default

Security is built into every layer:

- **Network isolation**: Private subnets by default with NAT Gateway for egress
- **Identity management**: Service accounts with least privilege
- **Secrets management**: No hardcoded secrets, Google Secret Manager integration
- **Encryption**: At-rest and in-transit encryption
- **Audit logging**: Comprehensive audit trails
- **Firewall rules**: Default deny with explicit allow rules

Security is built into every layer:

- **Network isolation**: Private subnets by default
- **Identity management**: Service accounts with least privilege
- **Secrets management**: No hardcoded secrets, Google Secret Manager integration
- **Encryption**: At-rest and in-transit encryption
- **Audit logging**: Comprehensive audit trails

**Rationale**:
- Compliance with security best practices
- Protection against common vulnerabilities
- Audit readiness
- Incident response capability

### 6. Operational Excellence

Focus on automation and observability:

- **CI/CD integration**: Automated validation and deployment
- **State management**: Remote state with locking
- **Monitoring**: Built-in observability
- **Documentation**: Self-documenting infrastructure

**Rationale**:
- Reduced operational overhead
- Faster incident resolution
- Knowledge preservation
- Team scalability

### 7. Clean State Deployments

Ensure infrastructure consistency through comprehensive resource management:

- **Complete teardown**: Remove all resources including IAM bindings
- **Fresh deployments**: Every deployment starts from a clean state
- **Configuration drift prevention**: No lingering configurations
- **Dependency integrity**: Proper recreation order maintained

**Rationale**:
- Prevents configuration drift
- Ensures reproducible deployments
- Simplifies troubleshooting
- Maintains security posture

## Design Patterns

### Template-Based Resource Creation

Resources are created using standardized templates:

```hcl
include "compute_template" {
  path = "${get_repo_root()}/_common/templates/compute_instance.hcl"
}
```

**Benefits**:
- Consistent resource configuration
- Centralized best practices
- Simplified resource creation
- Easy updates across all resources

### Explicit Dependency Management

Dependencies are explicitly declared:

```hcl
dependency "vpc-network" {
  config_path = "../vpc-network"
  mock_outputs = {
    network_name = "mock-network"
  }
}
```

**Benefits**:
- Clear infrastructure relationships
- Automated dependency resolution
- Safe parallel execution
- Simplified troubleshooting

### Centralized State Management

All state is stored in a centralized GCS bucket:

```hcl
remote_state {
  backend = "gcs"
  config = {
    bucket = "org-tofu-state"
    prefix = "${path_relative_to_include()}"
  }
}
```

**Benefits**:
- Team collaboration
- State locking prevents conflicts
- Backup and versioning
- Disaster recovery

### Module Version Pinning

All module versions are centrally managed:

```hcl
locals {
  compute_module_source = "tfr:///terraform-google-modules/vm/google//modules/compute_instance?version=12.0.0"
}
```

**Benefits**:
- Predictable behavior
- Controlled upgrades
- Easy rollbacks
- Compliance tracking

### Cloud Storage Pattern

Efficient data storage and retrieval:

```bash
# Direct cloud storage operations
gsutil cp local-file gs://bucket/path/
gsutil rsync -r local-dir/ gs://bucket/path/
```

**Benefits**:
- Scalable storage solution
- Built-in redundancy
- Cost-effective archival
- Global accessibility

## Infrastructure Organization

### Folder Hierarchy

The GCP organization follows a logical hierarchy:

```
Organization (example-org.com)
├── Bootstrap Folder
│   └── org-automation (Infrastructure management)
├── Development Folder
│   └── dp-dev-01 (Active development environment)
├── Perimeter Folder
│   └── Reserved for DMZ services
└── Production Folder
    └── Reserved for production workloads
```

**Rationale**:
- **Bootstrap**: Isolated management infrastructure
- **DMZ**: External-facing services with enhanced security
- **Clear boundaries**: Between infrastructure and application resources

### Project Structure

Projects are organized by function:

- **org-automation**: Infrastructure management and CI/CD
- **dp-dev-01**: Development environment with full stack
  - VPC Network (10.132.0.0/16)
  - GKE Cluster with ArgoCD
  - NAT Gateway for secure egress
  - Compute instances and databases
- **Future projects**: Follow the same patterns

**Benefits**:
- Resource isolation
- Cost tracking
- Security boundaries
- Quota management

### Regional Distribution

Resources are deployed regionally:

```
project/
└── europe-west2/
    ├── compute/
    ├── storage/
    └── network/
```

**Rationale**:
- Data residency compliance
- Latency optimization
- Disaster recovery
- Cost optimization

## Security Architecture

### Zero Trust Principles

- **No implicit trust**: All access must be authenticated and authorized
- **Least privilege**: Minimal permissions for each component
- **Defense in depth**: Multiple security layers
- **Continuous verification**: Regular security assessments

### Network Security

```
Internet → External IP → Cloud NAT → Cloud Router → Private Subnets → Resources
```

#### NAT Gateway Architecture
The infrastructure implements a centralized NAT Gateway pattern:

- **Cloud Router**: BGP router with ASN 64514 for dynamic routing
- **Cloud NAT**: Managed NAT service with automatic IP allocation
- **External IPs**: Reserved static IPs for predictable egress
- **Firewall Rules**: Explicit egress rules for NAT-enabled resources

Benefits:
- **Cost Optimization**: Single NAT gateway vs individual external IPs
- **Security**: Centralized egress control and monitoring
- **Scalability**: Automatic scaling based on traffic
- **Observability**: Comprehensive logging of all egress traffic

### Identity and Access Management

- **Service accounts**: Dedicated identities for each service
- **Role-based access**: Predefined roles for common patterns
- **Temporary credentials**: No long-lived keys where possible
- **Audit logging**: All access is logged

### Secret Management

```
Application → Secret Manager → Encrypted Storage
```

- **No hardcoded secrets**: All secrets in Secret Manager
- **Versioning**: Secret rotation capability
- **Access control**: Fine-grained permissions
- **Audit trail**: Access logging

### Secret Management Architecture

Comprehensive secrets management with GitOps integration:

#### Secret Categories
1. **Application Secrets**
   - SSL certificates and domains
   - API keys and tokens
   - Application credentials

2. **GKE/ArgoCD Secrets**
   - OAuth client credentials
   - Webhook URLs
   - Service account keys
   - GitHub personal access tokens

3. **Database Secrets**
   - Admin passwords
   - DBA credentials
   - Connection strings

#### External Secrets Operator Integration
Secrets are synchronized to Kubernetes using External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcpsm
spec:
  provider:
    gcpsm:
      projectID: "dp-dev-01"
      auth:
        workloadIdentity:
          clusterLocation: europe-west2
          clusterName: cluster-01
```

## Operational Considerations

### CI/CD Integration

The architecture supports comprehensive CI/CD:

1. **PR Validation**: Automatic plan generation
2. **Approval Gates**: Manual review for production
3. **Parallel Execution**: Efficient resource deployment
4. **Rollback Capability**: State-based recovery

### Cost Optimization

Built-in cost controls:

- **Environment-appropriate sizing**: Smaller resources for dev/test
- **Preemptible instances**: For fault-tolerant workloads
- **Automated shutdown**: For non-production resources
- **Resource tagging**: For cost attribution

### Monitoring and Observability

Comprehensive monitoring strategy:

- **Infrastructure metrics**: CPU, memory, disk, network
- **Application logs**: Centralized in Cloud Logging
- **Audit logs**: Security and compliance tracking
- **Alerts**: Proactive issue detection

### Disaster Recovery

Multi-level protection:

- **State backups**: Versioned state files
- **Infrastructure as Code**: Reproducible infrastructure
- **Data backups**: Automated backup strategies
- **Documentation**: Runbooks for common scenarios

### GitOps Platform Architecture

#### ArgoCD Bootstrap Configuration
The infrastructure includes a fully configured ArgoCD GitOps platform:

```hcl
# Bootstrap configuration with dynamic paths
locals {
  project_base_path = dirname(dirname(dirname(dirname(get_terragrunt_dir()))))
  secrets_base_path = "${local.project_base_path}/secrets"
}

dependency "argocd_oauth_secret" {
  config_path = "${local.secrets_base_path}/gke-argocd-oauth-client-secret"
}
```

#### Features
- **External Secrets Integration**: Automatic secret synchronization from Google Secret Manager
- **OAuth Authentication**: Google OAuth for secure access
- **Repository Sync**: GitHub repository integration for application deployment
- **Ingress Configuration**: External IP with sslip.io domain generation
- **Multi-cluster Support**: Ready for expansion to multiple clusters

### IP Allocation Management

Hierarchical IP allocation with comprehensive tracking:

#### IP Space Organization
- **Development**: 10.128.0.0/10 (4.2M IPs)
- **Perimeter**: 10.192.0.0/10 (4.2M IPs)  
- **Production**: 10.0.0.0/8 (16.7M IPs)
- **Total Managed**: ~25M IP addresses

#### Allocation Tracking
Centralized tracking in `ip-allocation.yaml` with validation tools:

```bash
# Validate allocations
python3 scripts/ip-allocation-checker.py validate

# Suggest next allocation
python3 scripts/ip-allocation-checker.py next dp-dev-01
```

## Scalability and Evolution

### Growth Patterns

The architecture supports several growth patterns:

1. **Horizontal scaling**: Add more instances of existing patterns
2. **New environments**: Clone existing environment configurations
3. **New regions**: Extend the regional pattern
4. **New projects**: Follow established project templates

### Module Extensibility

Easy to add new capabilities:

```hcl
# Add to _common/common.hcl
new_module_source = "tfr:///terraform-google-modules/new-module/google?version=1.0.0"
```

### Multi-Region Support

Built-in multi-region capabilities:

- **Regional templates**: Consistent cross-region deployment
- **Data replication**: Cross-region backup strategies
- **Traffic routing**: Global load balancing ready
- **Compliance**: Region-specific requirements

### Team Collaboration

Designed for team scalability:

- **Clear ownership**: Module and environment boundaries
- **Self-service**: Templates enable independent work
- **Peer review**: All changes through pull requests
- **Knowledge sharing**: Comprehensive documentation

## Future Considerations

### Implemented Patterns

The architecture has successfully implemented:

- **Kubernetes Platform**: GKE cluster with ArgoCD GitOps
- **NAT Gateway Pattern**: Centralized egress with Cloud NAT
- **Dynamic Configuration**: Terragrunt directory functions throughout
- **Secret Synchronization**: External Secrets Operator integration
- **IP Management**: Hierarchical allocation with validation

### Emerging Patterns

The architecture is prepared for:

- **Multi-cluster Expansion**: Support for cluster-02 through cluster-04
- **Serverless Integration**: Cloud Run and Functions ready
- **Data Platform**: BigQuery datasets already configured
- **ML/AI Workloads**: Infrastructure supports Vertex AI

### Continuous Improvement

Regular review cycles for:

- **Security updates**: Quarterly security reviews
- **Cost optimization**: Monthly cost analysis
- **Performance tuning**: Based on metrics
- **Documentation updates**: As patterns evolve
