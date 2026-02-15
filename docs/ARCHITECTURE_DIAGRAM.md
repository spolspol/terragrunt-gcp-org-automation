# GCP Infrastructure Architecture Diagram

This document provides a comprehensive visual representation of the GCP infrastructure managed by this repository, with clear relationship indicators and simplified connections.

## Overview

The infrastructure implements a hierarchical architecture with:
- **Organizational Structure**: GCP Organization → Folders (Bootstrap, Hub, Development) → Projects
- **Hub Services**: VPN gateway, centralised DNS, network connectivity, and PKI
- **Platform (dp-dev-01)**: GKE clusters, VMs, SQL Server, ArgoCD — fully private, VPN-only access
- **Functions (fn-dev-01)**: Cloud Run services, Load Balancer, Cloud Armor, PostgreSQL — serverless pattern
- **Network Architecture**: Fully private VPCs with egress-only internet access via Cloud NAT
- **VPN Access**: Users connect to all development projects via hub VPN Gateway with VPC peering
- **Security Components**: Secret Manager, IAM bindings, firewall rules, and Certificate Authority

## Visual Conventions

| Arrow Colour | Zone | Meaning |
|:-------------|:-----|:--------|
| **🔵 Blue** | Internet | Traffic to/from the public internet |
| **🔴 Red** | Public edge | VPN tunnel and public-facing endpoints |
| **🟢 Green** | Fully private | Internal traffic that never leaves private VPCs |

| Shape | Meaning |
|:------|:--------|
| **(Rounded rectangle)** | All nodes use rounded shapes with bold borders |
| **Bold text** | All labels use bold text for readability |

## Complete Infrastructure Architecture

```mermaid
graph TB
    %% ── External ────────────────────────────────────────────────
    subgraph External["<b>🌐 External Environment</b>"]
        Internet("<b>Internet</b>")
        GitHub("<b>GitHub Repositories</b>")
        Users("<b>Users / Clients</b>")
    end

    %% ── GCP Organization ────────────────────────────────────────
    subgraph GCPOrg["<b>🏢 GCP Organization (example-org.com)</b>"]

        %% Bootstrap
        subgraph Bootstrap["<b>📁 Bootstrap Folder</b>"]
            subgraph BootstrapProj["<b>🗂️ org-automation</b>"]
                StateStorage("<b>📦 Terraform State<br/>org-tofu-state bucket</b>")
                OrgSA("<b>🔑 Org Service Account<br/>tofu-sa-org@</b>")
            end
        end

        %% Hub
        subgraph Hub["<b>📁 Hub Folder</b>"]
            subgraph VPNGateway["<b>🗂️ vpn-gateway</b>"]
                VPNServer("<b>VPN Server</b>")
                VPNVPC("<b>VPN Gateway VPC</b>")
            end
            subgraph DNSHubProj["<b>🗂️ dns-hub</b>"]
                DNSZones("<b>Cloud DNS Zones</b>")
            end
            subgraph NetworkHubProj["<b>🗂️ network-hub</b>"]
                NCC("<b>Network Connectivity</b>")
            end
            subgraph PKIHubProj["<b>🗂️ pki-hub</b>"]
                CAS("<b>Certificate Authority</b>")
            end
        end

        %% Development
        subgraph Development["<b>📁 Development Folder</b>"]

            %% ── Platform sub-environment ──────────────────────
            subgraph DevProj["<b>🗂️ dp-dev-01 — Platform (Fully Private)</b>"]

                %% Network
                subgraph Network["<b>🌐 Network Layer (Private Only)</b>"]
                    VPC("<b>VPC Network<br/>10.132.0.0/16</b>")

                    subgraph Subnets["<b>Subnet Configuration</b>"]
                        DMZ("<b>DMZ: 10.132.0.0/21</b>")
                        Private("<b>Private: 10.132.8.0/21</b>")
                        GKESub("<b>GKE: 10.132.64.0/18</b>")
                    end

                    subgraph NATGateway["<b>NAT Gateway (Egress Only)</b>"]
                        Router("<b>Cloud Router<br/>BGP ASN: 64514</b>")
                        CloudNAT("<b>Cloud NAT</b>")
                        NATExtIP("<b>NAT External IP</b>")
                        Router ==> CloudNAT
                        CloudNAT ==> NATExtIP
                    end

                    VPC ==> Subnets
                    Subnets ==> Router
                end

                %% Compute
                subgraph Compute["<b>💻 Compute Resources</b>"]
                    subgraph GKECluster["<b>GKE Infrastructure</b>"]
                        GKE("<b>GKE Cluster<br/>cluster-01</b>")
                        ArgoCD("<b>ArgoCD Bootstrap</b>")
                        GKE ==> ArgoCD
                    end

                    subgraph VirtualMachines["<b>Virtual Machines</b>"]
                        LinuxVM("<b>Linux Server VM</b>")
                        WebVM("<b>Web Server VM</b>")
                        SQLVM("<b>SQL Server VM</b>")
                    end
                end

                %% Security
                subgraph Security["<b>🔒 Security Components</b>"]
                    Secrets("<b>Secret Manager<br/>13 secrets</b>")
                    IAM("<b>IAM Bindings</b>")
                    Firewall("<b>Firewall Rules</b>")
                end

                %% Storage
                subgraph Storage["<b>💾 Storage Services</b>"]
                    GCS("<b>Cloud Storage Buckets</b>")
                    BigQuery("<b>BigQuery Datasets</b>")
                    CloudSQL("<b>Cloud SQL Instances</b>")
                end
            end

            %% ── Functions sub-environment ─────────────────────
            subgraph FnProj["<b>🗂️ fn-dev-01 — Functions (Fully Private)</b>"]

                subgraph FnNetwork["<b>🌐 Network</b>"]
                    FnVPC("<b>VPC Network</b>")
                    FnNAT("<b>Cloud NAT</b>")
                end

                subgraph FnServerless["<b>☁️ Serverless</b>"]
                    FnCloudArmor("<b>Cloud Armor WAF</b>")
                    FnLB("<b>Load Balancer</b>")
                    FnCloudRun("<b>Cloud Run<br/>api-service · webhook-handler</b>")
                    FnCloudArmor ==> FnLB
                    FnLB ==> FnCloudRun
                end

                subgraph FnData["<b>💾 Data</b>"]
                    FnPostgres("<b>Cloud SQL<br/>PostgreSQL</b>")
                    FnArtifact("<b>Artifact Registry</b>")
                end

                subgraph FnSecurity["<b>🔒 Security</b>"]
                    FnSecrets("<b>Secrets</b>")
                    FnSA("<b>Service Accounts</b>")
                end
            end
        end
    end

    %% ── Traffic flows ───────────────────────────────────────────
    %% 🔴 Red — VPN / public edge
    Users ==>|"<b>VPN tunnel</b>"| VPNServer
    VPNServer ==> VPNVPC

    %% 🟢 Green — private peering
    VPNVPC ==>|"<b>VPC Peering</b>"| VPC
    VPNVPC ==>|"<b>VPC Peering</b>"| FnVPC

    %% 🔵 Blue — internet egress
    NATExtIP ==>|"<b>egress only</b>"| Internet
    FnNAT ==>|"<b>egress</b>"| Internet

    %% 🟢 Green — internal flows
    ArgoCD ==>|"<b>pull via NAT</b>"| CloudNAT
    GitHub -.->|"<b>synced via egress</b>"| ArgoCD
    VirtualMachines ==> CloudNAT
    GKE ==> CloudNAT
    FnVPC ==> FnNAT

    %% 🟢 Green — data / security flows
    Secrets -.-> ArgoCD
    Secrets -.-> VirtualMachines
    IAM -.-> Compute
    Firewall ==> Network
    StateStorage -.-> Development
    CloudSQL -.-> VirtualMachines
    FnCloudRun -.-> FnPostgres
    FnSecrets -.-> FnCloudRun

    %% ── Node styles ─────────────────────────────────────────────
    classDef internet fill:#bbdefb,stroke:#1565c0,stroke-width:3px,font-weight:bold,color:#000
    classDef public fill:#ffcdd2,stroke:#c62828,stroke-width:3px,font-weight:bold,color:#000
    classDef bootstrap fill:#b2dfdb,stroke:#00695c,stroke-width:3px,font-weight:bold,color:#000
    classDef hub fill:#ffe0b2,stroke:#e65100,stroke-width:3px,font-weight:bold,color:#000
    classDef network fill:#b3e5fc,stroke:#0277bd,stroke-width:3px,font-weight:bold,color:#000
    classDef compute fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,font-weight:bold,color:#000
    classDef serverless fill:#ffccbc,stroke:#d84315,stroke-width:3px,font-weight:bold,color:#000
    classDef security fill:#f8bbd0,stroke:#c2185b,stroke-width:3px,font-weight:bold,color:#000
    classDef storage fill:#e1bee7,stroke:#7b1fa2,stroke-width:3px,font-weight:bold,color:#000

    class Internet,GitHub internet
    class Users,VPNServer public
    class StateStorage,OrgSA bootstrap
    class VPNVPC,DNSZones,NCC,CAS hub
    class VPC,DMZ,Private,GKESub,Router,CloudNAT,NATExtIP,FnVPC,FnNAT network
    class GKE,ArgoCD,LinuxVM,WebVM,SQLVM compute
    class FnCloudRun,FnLB,FnCloudArmor serverless
    class Secrets,IAM,Firewall,FnSecrets,FnSA security
    class GCS,BigQuery,CloudSQL,FnPostgres,FnArtifact storage

    %% ── Link styles (by index) ──────────────────────────────────
    %% 0-4: dp-dev-01 internal structural (green)
    linkStyle 0 stroke:#2e7d32,stroke-width:3px
    linkStyle 1 stroke:#2e7d32,stroke-width:3px
    linkStyle 2 stroke:#2e7d32,stroke-width:3px
    linkStyle 3 stroke:#2e7d32,stroke-width:3px
    linkStyle 4 stroke:#2e7d32,stroke-width:3px
    %% 5-6: fn-dev-01 serverless chain (green)
    linkStyle 5 stroke:#2e7d32,stroke-width:3px
    linkStyle 6 stroke:#2e7d32,stroke-width:3px
    %% 7-8: VPN / public edge (red)
    linkStyle 7 stroke:#c62828,stroke-width:3px
    linkStyle 8 stroke:#c62828,stroke-width:3px
    %% 9-10: VPC peering (green)
    linkStyle 9 stroke:#2e7d32,stroke-width:3px
    linkStyle 10 stroke:#2e7d32,stroke-width:3px
    %% 11-12: NAT → Internet egress (blue)
    linkStyle 11 stroke:#1565c0,stroke-width:3px
    linkStyle 12 stroke:#1565c0,stroke-width:3px
    %% 13: ArgoCD pull (green)
    linkStyle 13 stroke:#2e7d32,stroke-width:3px
    %% 14: GitHub sync (blue — from internet)
    linkStyle 14 stroke:#1565c0,stroke-width:3px
    %% 15-17: internal egress (green)
    linkStyle 15 stroke:#2e7d32,stroke-width:3px
    linkStyle 16 stroke:#2e7d32,stroke-width:3px
    linkStyle 17 stroke:#2e7d32,stroke-width:3px
    %% 18-25: data / security flows (green, thinner)
    linkStyle 18 stroke:#2e7d32,stroke-width:2px
    linkStyle 19 stroke:#2e7d32,stroke-width:2px
    linkStyle 20 stroke:#2e7d32,stroke-width:2px
    linkStyle 21 stroke:#2e7d32,stroke-width:3px
    linkStyle 22 stroke:#2e7d32,stroke-width:2px
    linkStyle 23 stroke:#2e7d32,stroke-width:2px
    linkStyle 24 stroke:#2e7d32,stroke-width:2px
    linkStyle 25 stroke:#2e7d32,stroke-width:2px

    %% ── Subgraph styles ─────────────────────────────────────────
    %% Organisation
    style GCPOrg fill:#fafafa,stroke:#424242,stroke-width:3px,color:#000
    style External fill:#ffebee,stroke:#c62828,stroke-width:3px,color:#000

    %% Folders — warm yellow
    style Bootstrap fill:#fff8e1,stroke:#f9a825,stroke-width:3px,color:#000
    style Hub fill:#fff8e1,stroke:#f9a825,stroke-width:3px,color:#000
    style Development fill:#fff8e1,stroke:#f9a825,stroke-width:3px,color:#000

    %% Projects — cool indigo
    style BootstrapProj fill:#e8eaf6,stroke:#3949ab,stroke-width:3px,color:#000
    style VPNGateway fill:#e8eaf6,stroke:#3949ab,stroke-width:3px,color:#000
    style DNSHubProj fill:#e8eaf6,stroke:#3949ab,stroke-width:3px,color:#000
    style NetworkHubProj fill:#e8eaf6,stroke:#3949ab,stroke-width:3px,color:#000
    style PKIHubProj fill:#e8eaf6,stroke:#3949ab,stroke-width:3px,color:#000
    style DevProj fill:#e8eaf6,stroke:#3949ab,stroke-width:3px,color:#000
    style FnProj fill:#e8eaf6,stroke:#3949ab,stroke-width:3px,color:#000

    %% dp-dev-01 resource groups
    style Network fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    style Subnets fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px,color:#000
    style NATGateway fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#000
    style Compute fill:#e1f5fe,stroke:#0277bd,stroke-width:2px,color:#000
    style GKECluster fill:#b3e5fc,stroke:#0277bd,stroke-width:2px,color:#000
    style VirtualMachines fill:#b3e5fc,stroke:#0277bd,stroke-width:2px,color:#000
    style Security fill:#fce4ec,stroke:#c2185b,stroke-width:2px,color:#000
    style Storage fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#000

    %% fn-dev-01 resource groups
    style FnNetwork fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    style FnServerless fill:#fbe9e7,stroke:#d84315,stroke-width:2px,color:#000
    style FnData fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#000
    style FnSecurity fill:#fce4ec,stroke:#c2185b,stroke-width:2px,color:#000
```

## Detailed Component Views

### Network Architecture Detail

```mermaid
flowchart LR
    U("<b>Users</b>") ==>|"<b>VPN tunnel</b>"| VPN("<b>VPN Gateway<br/>Hub Project</b>")
    VPN ==>|"<b>VPC Peering</b>"| VPCDetail

    subgraph VPCDetail["<b>dp-dev-01 VPC (Fully Private — 10.132.0.0/16)</b>"]
        subgraph PrimaryNets["<b>Private Subnets</b>"]
            D("<b>DMZ<br/>10.132.0.0/21</b>")
            P("<b>Private<br/>10.132.8.0/21</b>")
            G("<b>GKE<br/>10.132.64.0/18</b>")
        end

        subgraph SecondaryNets["<b>GKE Secondary Ranges</b>"]
            POD("<b>Pods<br/>10.132.128.0/21</b>")
            SVC("<b>Services<br/>10.132.192.0/24</b>")
        end

        G -.-> POD
        G -.-> SVC
    end

    subgraph EgressPath["<b>Egress Only Path</b>"]
        CR("<b>Cloud Router</b>")
        CN("<b>Cloud NAT</b>")
        EIP("<b>External IP</b>")
        CR ==> CN ==> EIP
    end

    PrimaryNets ==> CR
    EIP ==>|"<b>egress only</b>"| I("<b>Internet</b>")

    %% Node styles
    classDef public fill:#ffcdd2,stroke:#c62828,stroke-width:3px,font-weight:bold,color:#000
    classDef private fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,font-weight:bold,color:#000
    classDef internet fill:#bbdefb,stroke:#1565c0,stroke-width:3px,font-weight:bold,color:#000
    classDef egress fill:#ffe0b2,stroke:#e65100,stroke-width:3px,font-weight:bold,color:#000

    class U public
    class VPN public
    class D,P,G,POD,SVC private
    class CR,CN,EIP egress
    class I internet

    %% Link styles
    linkStyle 0 stroke:#c62828,stroke-width:3px
    linkStyle 1 stroke:#2e7d32,stroke-width:3px
    linkStyle 2 stroke:#2e7d32,stroke-width:2px
    linkStyle 3 stroke:#2e7d32,stroke-width:2px
    linkStyle 4 stroke:#2e7d32,stroke-width:3px
    linkStyle 5 stroke:#2e7d32,stroke-width:3px
    linkStyle 6 stroke:#2e7d32,stroke-width:3px
    linkStyle 7 stroke:#1565c0,stroke-width:3px

    style VPCDetail fill:#e8f5e9,stroke:#2e7d32,stroke-width:3px,color:#000
    style EgressPath fill:#fff3e0,stroke:#e65100,stroke-width:3px,color:#000
```

### GitOps Architecture Detail

```mermaid
flowchart TB
    subgraph GitOpsStack["<b>GitOps Platform</b>"]
        subgraph Prerequisites["<b>Prerequisites</b>"]
            GKEC("<b>GKE Cluster</b>")
            SECS("<b>Secrets</b>")
            EXTIP("<b>External IP</b>")
        end

        subgraph ArgoComponents["<b>ArgoCD Components</b>"]
            ARGO("<b>ArgoCD Core</b>")
            ESO("<b>External Secrets<br/>Operator</b>")
            INGRESS("<b>Ingress Controller</b>")
        end

        subgraph Applications["<b>Deployed Apps</b>"]
            APPS("<b>Application<br/>Manifests</b>")
            CONFIGS("<b>ConfigMaps</b>")
            DEPLOYS("<b>Deployments</b>")
        end
    end

    GKEC ==> ARGO
    SECS -.-> ESO
    ESO -.-> ARGO
    EXTIP ==> INGRESS
    ARGO ==> Applications

    GITHUB("<b>GitHub Repos</b>") -.->|"<b>via NAT egress</b>"| ARGO

    classDef prereq fill:#ffe0b2,stroke:#e65100,stroke-width:3px,font-weight:bold,color:#000
    classDef argo fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,font-weight:bold,color:#000
    classDef apps fill:#dcedc8,stroke:#33691e,stroke-width:3px,font-weight:bold,color:#000
    classDef ext fill:#bbdefb,stroke:#1565c0,stroke-width:3px,font-weight:bold,color:#000

    class GKEC,SECS,EXTIP prereq
    class ARGO,ESO,INGRESS argo
    class APPS,CONFIGS,DEPLOYS apps
    class GITHUB ext

    linkStyle 0 stroke:#2e7d32,stroke-width:3px
    linkStyle 1 stroke:#2e7d32,stroke-width:2px
    linkStyle 2 stroke:#2e7d32,stroke-width:2px
    linkStyle 3 stroke:#2e7d32,stroke-width:3px
    linkStyle 4 stroke:#2e7d32,stroke-width:3px
    linkStyle 5 stroke:#1565c0,stroke-width:3px

    style GitOpsStack fill:#e8f5e9,stroke:#2e7d32,stroke-width:3px,color:#000
    style Prerequisites fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#000
    style ArgoComponents fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px,color:#000
    style Applications fill:#dcedc8,stroke:#33691e,stroke-width:2px,color:#000
```

### Security Layer Detail

```mermaid
flowchart TD
    subgraph SecurityComponents["<b>Security Architecture</b>"]
        subgraph SecretsManagement["<b>Secrets Management</b>"]
            SM("<b>Secret Manager</b>")
            subgraph SecretTypes["<b>Secret Categories</b>"]
                GKE_SEC("<b>GKE Secrets<br/>• OAuth Tokens<br/>• Webhooks<br/>• Service Accounts</b>")
                APP_SEC("<b>App Secrets<br/>• SSL Certs<br/>• API Keys</b>")
                DB_SEC("<b>Database<br/>• Admin Password<br/>• DBA Password</b>")
            end
            SM ==> SecretTypes
        end

        subgraph AccessControl["<b>Access Control</b>"]
            IAM_BIND("<b>IAM Bindings</b>")
            SA("<b>Service Accounts</b>")
            RBAC("<b>GKE RBAC</b>")
        end

        subgraph NetworkSecurity["<b>Network Security</b>"]
            FW("<b>Firewall Rules</b>")
            PSA("<b>Private Service<br/>Access</b>")
            NAT_SEC("<b>NAT Gateway<br/>Security</b>")
        end
    end

    SecretsManagement -.-> AccessControl
    AccessControl ==> NetworkSecurity

    classDef secrets fill:#f8bbd0,stroke:#c2185b,stroke-width:3px,font-weight:bold,color:#000
    classDef access fill:#e1bee7,stroke:#7b1fa2,stroke-width:3px,font-weight:bold,color:#000
    classDef netsec fill:#ffcdd2,stroke:#c62828,stroke-width:3px,font-weight:bold,color:#000

    class SM,GKE_SEC,APP_SEC,DB_SEC secrets
    class IAM_BIND,SA,RBAC access
    class FW,PSA,NAT_SEC netsec

    linkStyle 0 stroke:#c2185b,stroke-width:3px
    linkStyle 1 stroke:#7b1fa2,stroke-width:2px
    linkStyle 2 stroke:#7b1fa2,stroke-width:3px

    style SecurityComponents fill:#fce4ec,stroke:#c2185b,stroke-width:3px,color:#000
    style SecretsManagement fill:#fce4ec,stroke:#c2185b,stroke-width:2px,color:#000
    style AccessControl fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#000
    style NetworkSecurity fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#000
```

## Resource Dependency Graph

```mermaid
graph LR
    subgraph Foundation["<b>Foundation</b>"]
        ORG("<b>Organization</b>")
        FOLDER("<b>Folders</b>")
        PROJECT("<b>Projects</b>")
        ORG ==> FOLDER ==> PROJECT
    end

    subgraph Infrastructure["<b>Infrastructure</b>"]
        VPC_NET("<b>VPC Network</b>")
        EXT_IP("<b>External IPs</b>")
        ROUTER("<b>Cloud Router</b>")
        NAT("<b>Cloud NAT</b>")
        PROJECT ==> VPC_NET
        VPC_NET ==> ROUTER
        ROUTER ==> NAT
        PROJECT ==> EXT_IP
    end

    subgraph Resources["<b>Resources</b>"]
        GKE_RES("<b>GKE Clusters</b>")
        VM_RES("<b>VM Instances</b>")
        DB_RES("<b>Databases</b>")
        NAT ==> GKE_RES
        NAT ==> VM_RES
        VPC_NET ==> DB_RES
    end

    subgraph Platform["<b>Platform</b>"]
        ARGOCD("<b>ArgoCD</b>")
        APPS("<b>Applications</b>")
        GKE_RES ==> ARGOCD
        ARGOCD ==> APPS
    end

    classDef found fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,font-weight:bold,color:#000
    classDef infra fill:#bbdefb,stroke:#1565c0,stroke-width:3px,font-weight:bold,color:#000
    classDef res fill:#ffe0b2,stroke:#e65100,stroke-width:3px,font-weight:bold,color:#000
    classDef plat fill:#dcedc8,stroke:#33691e,stroke-width:3px,font-weight:bold,color:#000

    class ORG,FOLDER,PROJECT found
    class VPC_NET,EXT_IP,ROUTER,NAT infra
    class GKE_RES,VM_RES,DB_RES res
    class ARGOCD,APPS plat

    linkStyle default stroke:#2e7d32,stroke-width:3px

    style Foundation fill:#e8f5e9,stroke:#2e7d32,stroke-width:3px,color:#000
    style Infrastructure fill:#e3f2fd,stroke:#1565c0,stroke-width:3px,color:#000
    style Resources fill:#fff3e0,stroke:#e65100,stroke-width:3px,color:#000
    style Platform fill:#dcedc8,stroke:#33691e,stroke-width:3px,color:#000
```

## IP Allocation Overview

```mermaid
pie title "IP Space Utilization (dp-dev-01)"
    "DMZ Subnet" : 2048
    "Private Subnet" : 2048
    "GKE Primary" : 16384
    "GKE Pods" : 2048
    "GKE Services" : 256
    "Reserved" : 33792
```

## Deployment Flow

```mermaid
sequenceDiagram
    box rgb(255,205,210) Public Edge
        participant User
        participant VPN as VPN Gateway
    end
    box rgb(187,222,251) Internet
        participant GitHub
    end
    box rgb(200,230,201) Fully Private
        participant Terragrunt
        participant GCP as GCP (dp-dev-01)
        participant ArgoCD
    end

    User->>GitHub: Push infrastructure code
    GitHub->>Terragrunt: Trigger CI/CD
    Terragrunt->>GCP: Apply infrastructure
    GCP-->>Terragrunt: Resources created
    Terragrunt->>ArgoCD: Deploy bootstrap
    ArgoCD->>GitHub: Sync applications (via NAT egress)
    ArgoCD->>GCP: Deploy workloads
    User->>VPN: Connect via VPN
    VPN->>GCP: Route to private VPC (peering)
    GCP-->>User: Access private resources
```

## Key Features Highlighted

### 1. **Hierarchical Organization**
- Clear folder structure: Organization → Folders → Projects → Resources
- Environment separation (Development/Perimeter/Production)
- Sub-environments: **Platform** (dp-dev-01) for GKE/VMs, **Functions** (fn-dev-01) for Cloud Run

### 2. **Hub Services**
- **vpn-gateway**: VPN server and VPC peering to all development projects
- **dns-hub**: Centralised Cloud DNS zone management
- **network-hub**: Network connectivity centre
- **pki-hub**: Certificate Authority Service for internal PKI

### 3. **Network Security**
- Fully private VPCs — no public ingress to development projects
- User access exclusively via VPN through hub VPN Gateway with VPC peering
- Egress-only internet access through Cloud NAT for outbound traffic (image pulls, updates)
- Firewall rules and Private Service Access

### 4. **GitOps Integration**
- ArgoCD for continuous delivery (dp-dev-01)
- External Secrets Operator
- GitHub repository synchronisation

### 5. **Serverless Pattern (fn-dev-01)**
- Cloud Run services behind Load Balancer with Cloud Armor WAF
- Cloud SQL PostgreSQL for persistent data
- Artifact Registry for container images
- Dedicated service accounts for deployment and runtime

### 6. **Scalability**
- Support for multiple GKE clusters and Cloud Run services
- Reserved IP ranges for growth
- Modular Terragrunt configuration

## Navigation

- [Architecture Summary](ARCHITECTURE_SUMMARY.md) - Design principles and rationale
- [Network Architecture](NETWORK_ARCHITECTURE.md) - Detailed network design
- [GitOps Architecture](GITOPS_ARCHITECTURE.md) - ArgoCD and deployment patterns
- [IP Allocation](IP_ALLOCATION.md) - IP address management
- [Current State](CURRENT_STATE.md) - Live infrastructure status