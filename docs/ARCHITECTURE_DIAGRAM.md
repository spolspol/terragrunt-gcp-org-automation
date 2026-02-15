# GCP Infrastructure Architecture Diagram

This document provides a comprehensive visual representation of the GCP infrastructure managed by this repository, with clear relationship indicators and simplified connections.

## Overview

The infrastructure implements a hierarchical architecture with:
- **Organizational Structure**: GCP Organization with folder hierarchy
- **Environment Separation**: Development, perimeter, and production environments  
- **Network Architecture**: VPC with NAT Gateway for secure egress
- **Compute Resources**: GKE clusters, VMs, and SQL Server
- **GitOps Platform**: ArgoCD for continuous delivery
- **Security Components**: Secret Manager, IAM bindings, and firewall rules

## Visual Conventions

| Line Style | Meaning | Example |
|------------|---------|---------|
| Solid (→) | Direct dependency/ownership | VPC → Subnet |
| Dashed (-->) | Network flow with direction | VM --> NAT |
| Dotted (..>) | Data flow | Secrets ..> Application |
| Double (<-->) | Bidirectional communication | Client <--> Server |
| No arrow | Structural relationship | Parent contains Child |

## Complete Infrastructure Architecture

```mermaid
graph TB
    %% External Components
    subgraph External["🌐 External Environment"]
        Internet["Internet"]
        GitHub["GitHub Repositories"]
        Users["Users/Clients"]
    end

    %% GCP Organization Structure
    subgraph GCPOrg["🏢 GCP Organization (example-org.com)"]
        
        %% Bootstrap Foundation
        subgraph Bootstrap["📁 Bootstrap Folder"]
            subgraph BootstrapProj["🗂️ org-automation Project"]
                StateStorage["📦 Terraform State<br/>org-tofu-state bucket"]
                OrgSA["🔑 Org Service Account<br/>tofu-sa-org@"]
            end
        end
        
        %% Development Environment
        subgraph Development["📁 Development Folder"]
            subgraph DevProj["🗂️ dp-dev-01 Project"]
                
                %% Core Networking
                subgraph Network["🌐 Network Layer"]
                    VPC["VPC Network<br/>10.132.0.0/16"]
                    
                    subgraph Subnets["Subnet Configuration"]
                        DMZ["DMZ: 10.132.0.0/21"]
                        Private["Private: 10.132.8.0/21"]
                        Public["Public: 10.132.16.0/21"]
                        GKESub["GKE: 10.132.64.0/18"]
                    end
                    
                    subgraph NATGateway["NAT Gateway Stack"]
                        Router["Cloud Router<br/>BGP ASN: 64514"]
                        CloudNAT["Cloud NAT"]
                        NATExtIP["NAT External IP"]
                        Router --> CloudNAT
                        CloudNAT --> NATExtIP
                    end
                    
                    VPC --> Subnets
                    Subnets --> Router
                end
                
                %% Compute Resources
                subgraph Compute["💻 Compute Resources"]
                    subgraph GKECluster["GKE Infrastructure"]
                        GKE["GKE Cluster<br/>cluster-01"]
                        ArgoCD["ArgoCD Bootstrap"]
                        GKEExtIP["Ingress External IP"]
                        GKE --> ArgoCD
                    end
                    
                    subgraph VirtualMachines["Virtual Machines"]
                        LinuxVM["Linux Server VM"]
                        WebVM["Web Server VM"]
                        SQLVM["SQL Server VM"]
                    end
                end
                
                %% Security Layer
                subgraph Security["🔒 Security Components"]
                    Secrets["Secret Manager<br/>13 secrets"]
                    IAM["IAM Bindings"]
                    Firewall["Firewall Rules"]
                end
                
                %% Storage Layer
                subgraph Storage["💾 Storage Services"]
                    GCS["Cloud Storage Buckets"]
                    BigQuery["BigQuery Datasets"]
                    CloudSQL["Cloud SQL Instances"]
                end
            end
        end
    end

    %% Primary Connections (Simplified)
    
    %% External Connections
    NATExtIP --> Internet
    GKEExtIP --> Internet
    Users --> GKEExtIP
    GitHub -.-> ArgoCD
    
    %% Internal Network Flow  
    VirtualMachines --> CloudNAT
    GKE --> CloudNAT
    
    %% Security Relationships
    Secrets -.-> ArgoCD
    Secrets -.-> VirtualMachines
    IAM -.-> Compute
    Firewall --> Network
    
    %% Data Flow
    StateStorage -.-> Development
    CloudSQL -.-> VirtualMachines
    
    %% Styling
    classDef external fill:#ffebee,stroke:#c62828,stroke-width:2px
    classDef org fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef network fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef compute fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef security fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    classDef storage fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    
    class External external
    class GCPOrg,Bootstrap,Development org
    class Network,VPC,NATGateway network
    class Compute,GKECluster,VirtualMachines compute
    class Security security
    class Storage storage
```

## Detailed Component Views

### Network Architecture Detail

```mermaid
flowchart LR
    subgraph VPCDetail["VPC Network (10.132.0.0/16)"]
        subgraph PrimaryNets["Primary Subnets"]
            D[DMZ<br/>10.132.0.0/21]
            P[Private<br/>10.132.8.0/21]
            PU[Public<br/>10.132.16.0/21]
            G[GKE<br/>10.132.64.0/18]
        end
        
        subgraph SecondaryNets["GKE Secondary Ranges"]
            POD[Pods<br/>10.132.128.0/21]
            SVC[Services<br/>10.132.192.0/24]
        end
        
        G -.-> POD
        G -.-> SVC
    end
    
    subgraph EgressPath["Egress Path"]
        CR[Cloud Router]
        CN[Cloud NAT]
        EIP[External IP]
        CR --> CN --> EIP
    end
    
    PrimaryNets --> CR
    EIP --> I[Internet]
    
    style VPCDetail fill:#e3f2fd
    style EgressPath fill:#fff3e0
```

### GitOps Architecture Detail

```mermaid
flowchart TB
    subgraph GitOpsStack["GitOps Platform"]
        subgraph Prerequisites["Prerequisites"]
            GKEC[GKE Cluster]
            SECS[Secrets]
            EXTIP[External IP]
        end
        
        subgraph ArgoComponents["ArgoCD Components"]
            ARGO[ArgoCD Core]
            ESO[External Secrets<br/>Operator]
            INGRESS[Ingress Controller]
        end
        
        subgraph Applications["Deployed Apps"]
            APPS[Application<br/>Manifests]
            CONFIGS[ConfigMaps]
            DEPLOYS[Deployments]
        end
    end
    
    GKEC --> ARGO
    SECS -.-> ESO
    ESO -.-> ARGO
    EXTIP --> INGRESS
    ARGO --> Applications
    
    GITHUB[GitHub Repos] -.-> ARGO
    
    style GitOpsStack fill:#c5e1a5
    style Prerequisites fill:#fff3e0
    style ArgoComponents fill:#dcedc8
    style Applications fill:#f1f8e9
```

### Security Layer Detail

```mermaid
flowchart TD
    subgraph SecurityComponents["Security Architecture"]
        subgraph SecretsManagement["Secrets Management"]
            SM[Secret Manager]
            subgraph SecretTypes["Secret Categories"]
                GKE_SEC[GKE Secrets<br/>• OAuth Tokens<br/>• Webhooks<br/>• Service Accounts]
                APP_SEC[App Secrets<br/>• SSL Certs<br/>• API Keys]
                DB_SEC[Database<br/>• Admin Password<br/>• DBA Password]
            end
            SM --> SecretTypes
        end
        
        subgraph AccessControl["Access Control"]
            IAM_BIND[IAM Bindings]
            SA[Service Accounts]
            RBAC[GKE RBAC]
        end
        
        subgraph NetworkSecurity["Network Security"]
            FW[Firewall Rules]
            PSA[Private Service<br/>Access]
            NAT_SEC[NAT Gateway<br/>Security]
        end
    end
    
    SecretsManagement -.-> AccessControl
    AccessControl --> NetworkSecurity
    
    style SecurityComponents fill:#fce4ec
    style SecretsManagement fill:#f8bbd0
    style AccessControl fill:#f48fb1
    style NetworkSecurity fill:#f06292
```

## Resource Dependency Graph

```mermaid
graph LR
    subgraph Foundation
        ORG[Organization]
        FOLDER[Folders]
        PROJECT[Projects]
        ORG --> FOLDER --> PROJECT
    end
    
    subgraph Infrastructure
        VPC_NET[VPC Network]
        EXT_IP[External IPs]
        ROUTER[Cloud Router]
        NAT[Cloud NAT]
        PROJECT --> VPC_NET
        VPC_NET --> ROUTER
        ROUTER --> NAT
        PROJECT --> EXT_IP
    end
    
    subgraph Resources
        GKE_RES[GKE Clusters]
        VM_RES[VM Instances]
        DB_RES[Databases]
        NAT --> GKE_RES
        NAT --> VM_RES
        VPC_NET --> DB_RES
    end
    
    subgraph Platform
        ARGOCD[ArgoCD]
        APPS[Applications]
        GKE_RES --> ARGOCD
        ARGOCD --> APPS
    end
    
    style Foundation fill:#e8f5e9
    style Infrastructure fill:#e3f2fd  
    style Resources fill:#fff3e0
    style Platform fill:#c5e1a5
```

## IP Allocation Overview

```mermaid
pie title "IP Space Utilization (dp-dev-01)"
    "DMZ Subnet" : 2048
    "Private Subnet" : 2048
    "Public Subnet" : 2048
    "GKE Primary" : 16384
    "GKE Pods" : 2048
    "GKE Services" : 256
    "Reserved" : 31744
```

## Deployment Flow

```mermaid
sequenceDiagram
    participant User
    participant GitHub
    participant Terragrunt
    participant GCP
    participant ArgoCD
    
    User->>GitHub: Push infrastructure code
    GitHub->>Terragrunt: Trigger CI/CD
    Terragrunt->>GCP: Apply infrastructure
    GCP-->>Terragrunt: Resources created
    Terragrunt->>ArgoCD: Deploy bootstrap
    ArgoCD->>GitHub: Sync applications
    ArgoCD->>GCP: Deploy workloads
    GCP-->>User: Infrastructure ready
```

## Key Features Highlighted

### 1. **Hierarchical Organization**
- Clear folder structure from Organization to Projects
- Environment separation (Development/Perimeter/Production)
- Logical resource grouping

### 2. **Network Security**
- Private subnets with NAT Gateway
- Centralized egress control
- Firewall rules and Private Service Access

### 3. **GitOps Integration**
- ArgoCD for continuous delivery
- External Secrets Operator
- GitHub repository synchronization

### 4. **Comprehensive Monitoring**
- State tracking in GCS
- Secret management
- IAM controls

### 5. **Scalability**
- Support for multiple GKE clusters
- Reserved IP ranges for growth
- Modular Terragrunt configuration

## Navigation

- [Architecture Summary](ARCHITECTURE_SUMMARY.md) - Design principles and rationale
- [Network Architecture](NETWORK_ARCHITECTURE.md) - Detailed network design
- [GitOps Architecture](GITOPS_ARCHITECTURE.md) - ArgoCD and deployment patterns
- [IP Allocation](IP_ALLOCATION.md) - IP address management
- [Current State](CURRENT_STATE.md) - Live infrastructure status