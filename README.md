# Terragrunt GCP Infrastructure Live

This repository manages Google Cloud Platform (GCP) infrastructure using Terragrunt and OpenTofu, following best practices from Gruntwork's reference architecture.

## Workflow Status

[![Terragrunt PR Engine](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/terragrunt-pr-engine.yml/badge.svg)](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/terragrunt-pr-engine.yml)
[![Terragrunt Apply Engine](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/terragrunt-apply-engine.yml/badge.svg)](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/terragrunt-apply-engine.yml)
[![Manage Compute Instance](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/manage-compute-instance.yml/badge.svg)](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/manage-compute-instance.yml)
[![Manage SQL Instance](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/manage-sql-instance.yml/badge.svg)](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/manage-sql-instance.yml)
[![Upload VM Scripts](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/upload-vm-scripts.yml/badge.svg)](https://github.com/example-org/terragrunt-gcp-automation/actions/workflows/upload-vm-scripts.yml)

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Essential Commands](#essential-commands)
- [Documentation](#documentation)
- [Key Features](#key-features)
- [CI/CD Workflows](#cicd-workflows)
- [Development Best Practices](#development-best-practices)
- [Recent Updates](#recent-updates)
- [References](#references)

## Overview

This infrastructure-as-code repository implements a hierarchical configuration approach for managing GCP resources across multiple environments. It uses:

- **OpenTofu v1.9.1** (Terraform alternative) as the infrastructure provisioning engine
- **Terragrunt v0.80.2** for configuration management and DRY infrastructure code
- **Reusable templates** for standardized resource configuration
- **Hierarchical structure** for environment/account/project organization
- **Folder-based organization** for GCP resource hierarchy
- **GitHub Actions** for automated CI/CD workflows

> **Note**: This repository uses `root.hcl` instead of `terragrunt.hcl` as the root configuration file.

## Repository Structure

```
tg-gcp-infra-live/
├── _common/                    # Common configurations and templates
│   ├── common.hcl              # Shared variables and module versions
│   └── templates/              # Reusable resource templates
├── docs/                       # Detailed documentation
│   ├── BOOTSTRAP.md            # Complete bootstrap setup guide
│   └── ...                     # Other documentation files
├── .github/workflows/          # CI/CD automation workflows
├── scripts/                    # Helper scripts for automation
│   ├── parse_resource_order.py # Parses and visualizes resource dependencies
│   ├── setup-pre-commit.sh     # Sets up pre-commit hooks
│   └── save-plan-artifact.sh   # Saves Terragrunt plan artifacts
├── live/                       # Live infrastructure by environment
│   └── account/                # Account level
│       ├── account.hcl         # Account-level variables
│       └── environment/        # Environment level (dev, staging, prod)
│           ├── env.hcl         # Environment-wide settings
│           ├── folder/         # GCP folder creation
│           │   └── terragrunt.hcl
│           └── project-name/   # Project level
│               ├── project.hcl # Project-specific variables
│               ├── project/    # Project creation
│               │   └── terragrunt.hcl
│               ├── vpc-network/ # VPC network resources
│               │   ├── terragrunt.hcl
│               │   └── private-service-access/
│               │       └── terragrunt.hcl
│               ├── secrets/    # Secret management
│               │   ├── secrets.hcl
│               │   └── secret-name/
│               │       └── terragrunt.hcl
│               ├── firewall-rules/ # Firewall rules configuration
│               │   └── terragrunt.hcl
│               ├── external-ip/  # External IP reservations
│               │   └── terragrunt.hcl
│               ├── iam-bindings/ # IAM role bindings
│               │   └── terragrunt.hcl
│               └── region/     # Region level
│                   ├── region.hcl
│                   ├── bigquery/
│                   │   └── terragrunt.hcl
│                   ├── compute/
│                   │   ├── compute.hcl
│                   │   └── vm-name/
│                   │       ├── instance-template/
│                   │       │   └── terragrunt.hcl
│                   │       ├── iam-bindings/
│                   │       │   └── terragrunt.hcl
│                   │       ├── scripts/
│                   │       │   └── *.sh    # VM-specific scripts
│                   │       └── terragrunt.hcl
│                   ├── cloud-sql/
│                   │   └── sql-server-01/
│                   │       └── terragrunt.hcl
│                   └── buckets/
│                       ├── vm-scripts/
│                       │   └── terragrunt.hcl
├── root.hcl                    # Root configuration
└── QUICKSTART.md               # Quick start guide
```

## Quick Start

1. **Bootstrap Infrastructure (Recommended)**
   ```bash
   # Clone the repository
   git clone https://github.com/your-org/tg-gcp-infra-live.git
   cd tg-gcp-infra-live
   
   # Run the bootstrap script to set up foundational infrastructure
   ./scripts/org-bootstrap.sh
   
   # This creates:
   # - GCP Folder: org-bootstrap 
   # - GCP Project: org-automation
   # - Service Account: tofu-sa-org with organization-level permissions
   # - State Bucket: org-tofu-state
   # - Billing Bucket: org-billing-usage-reports
   # - Helper scripts for project permissions
   
   # Set up authentication using the bootstrap service account
   export GOOGLE_APPLICATION_CREDENTIALS="$HOME/tofu-sa-org-key.json"
   source scripts/setup_env.sh
   
   # For secrets management:
   source scripts/setup_secrets_env.sh
   ```

2. **Manual Setup (Alternative)**
   - **Prerequisites**
     - OpenTofu ≥ 1.9.1
     - Terragrunt ≥ 0.80.2
     - Google Cloud SDK
     - GCP Service Account with appropriate permissions

   ```bash
   # Set up environment variables
   source scripts/setup_env.sh
   
   # Set up GCP authentication
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
   
   # Deploy infrastructure in dependency order:
   
   # 1. Create the folder first
   cd live/account/environment/folder
   terragrunt init && terragrunt apply
   
   # 2. Create the project (depends on folder)
   cd ../project-name/project
   terragrunt init && terragrunt apply
   
   # 3. Create VPC network (depends on project)
   cd ../vpc-network
   terragrunt init && terragrunt apply
   
   # 4. Create private service access (depends on VPC network)
   cd private-service-access
   terragrunt init && terragrunt apply
   
   # 5. Deploy regional resources (depends on project and network)
   cd ../region/bigquery
   terragrunt init && terragrunt apply
   ```

For detailed setup instructions, see [Bootstrap Guide](docs/BOOTSTRAP.md), [QUICKSTART.md](QUICKSTART.md), [OpenTofu Setup Guide](docs/OPENTOFU_SETUP.md) and [GCP Authentication Guide](docs/GCP_AUTHENTICATION.md).

## Essential Commands

### Terragrunt Commands (Never use terraform/tofu directly)
```bash
# Navigate to resource directory first
cd live/account/environment/project-name/resource

# Standard workflow
terragrunt init
terragrunt plan
terragrunt apply
terragrunt destroy
terragrunt validate

# Common flags
terragrunt plan --terragrunt-non-interactive
terragrunt apply --auto-approve
```

### VM Scripts Management
```bash
# Manually upload VM scripts to GCS buckets
gh workflow run upload-vm-scripts.yml

# Force upload all scripts (even if no changes)
gh workflow run upload-vm-scripts.yml --field force_upload=true
```

### Pre-commit Setup
```bash
./scripts/setup-pre-commit.sh
# Runs terragrunt fmt, secret detection, YAML formatting
```

### Resource Dependency Analysis
```bash
# Visualize resource dependencies and deployment order
python scripts/parse_resource_order.py
```

### Manual Workflow Execution
```bash
# Deploy/destroy specific compute instance
gh workflow run manage-compute-instance.yml \
  --field action=deploy \
  --field instance=project/instance
# Example: --field instance=org-dev-01/web-server-01

# Manage SQL Server instance
gh workflow run manage-sql-instance.yml \
  --field action=deploy \
  --field instance=project/instance
```

## Documentation

| Document | Description |
|----------|-------------|
| [Bootstrap Guide](docs/BOOTSTRAP.md) | **Complete GCP bootstrap setup** - Creates foundational infrastructure automatically |
| [OpenTofu Setup](docs/OPENTOFU_SETUP.md) | Setting up and using OpenTofu with this repository |
| [GCP Authentication](docs/GCP_AUTHENTICATION.md) | Setting up authentication with GCP service accounts |
| [Root Configuration](docs/ROOT_CONFIGURATION.md) | Details about the root.hcl configuration |
| [GitHub Workflows](docs/WORKFLOWS.md) | Comprehensive guide to CI/CD workflows and automation |
| [Configuration Templates](docs/CONFIGURATION_TEMPLATES.md) | Using and creating reusable templates |
| [Folder Template](docs/FOLDER_TEMPLATE.md) | Guide for the GCP Folder template |
| [Project Template](docs/PROJECT_TEMPLATE.md) | Guide for the Project Factory template |
| [Network Template](docs/NETWORK_TEMPLATE.md) | Guide for the Network (VPC) template |
| [Private Service Access Template](docs/PRIVATE_SERVICE_ACCESS_TEMPLATE.md) | Guide for the Private Service Access template |
| [Cloud SQL Template](docs/SQLSERVER_TEMPLATE.md) | Guide for the MSSQL 2019 Web Edition template |
| [BigQuery Template](docs/BIGQUERY_TEMPLATE.md) | Guide for the BigQuery template |
| [Buckets Template](docs/BUCKETS_TEMPLATE.md) | Guide for the Cloud Storage buckets template |
| [Compute Template](docs/COMPUTE_TEMPLATE.md) | Guide for the Compute Instance template and multi-VM architecture |
| [Secrets Template](docs/SECRETS_TEMPLATE.md) | Guide for the individual Secrets template and multi-secret architecture |
| [Secret Management](docs/SECRET_MANAGEMENT.md) | Best practices for secret management |
| [Module Versioning](docs/MODULE_VERSIONING.md) | Managing module versions consistently |
| [Data Staging Infrastructure](docs/DATA_STAGING.md) | Complete guide for data-staging compute resources and workflows |
| [IAM Bindings Template](docs/IAM_BINDINGS_TEMPLATE.md) | Guide for the IAM bindings template and service account permissions |
| [Architecture Summary](docs/ARCHITECTURE_SUMMARY.md) | High-level architecture overview and design decisions |

## Key Features

### Hierarchical Configuration
- **Account Level**: Organization-wide settings and billing configuration
- **Environment Level**: Environment-specific settings (dev, staging, prod)
- **Project Level**: Project-specific configuration and resources
- **Regional Level**: Region-specific resources and settings

### CI/CD Automation
Sophisticated GitHub Actions workflows provide:
- **Automated validation** on pull requests with detailed plan output
- **Orchestrated deployment** respecting resource dependencies
- **Parallel execution** where possible (VPC networks + secrets)
- **Environment protection** with manual approval for production
- **Comprehensive reporting** with PR comments and step summaries
- **Automated script deployment** to GCS buckets after infrastructure changes

### Dependency Management
The infrastructure follows a clear dependency hierarchy:
1. **Folder** → Creates GCP organizational folders
2. **Project** → Creates GCP projects within folders
3. **VPC Network** → Creates networking infrastructure
4. **Private Service Access** → Enables private connectivity for Google services
5. **Regional Resources** → Deploys compute instances, storage, and database resources

### Key Infrastructure Components

#### Example Web Server
- **Purpose**: Demonstrates compute instance deployment patterns
- **Architecture**: Standard web server configuration with nginx
- **Script Components**:
  - `startup-script.sh` - Instance initialization and configuration
  - Web server setup and configuration
  - Health check endpoints
  - Logging integration
- **Features**: 
  - Auto-scaling ready
  - Load balancer compatible
  - Cloud CDN integration
- **Security**: Firewall rules, IAM-based access control, SSL/TLS support

#### SQL Server Infrastructure
- **Version**: MSSQL 2019 Web Edition
- **Features**: Dynamic NetBIOS naming, GCS bucket mounting, automated DBA user setup
- **Security**: Private networking, SSL enforcement, encrypted backups

### Template System
Standardized templates ensure consistent resource configuration:
- **Environment-aware settings** (production vs. non-production)
- **Centralized module versioning** in `_common/common.hcl`
- **Reusable configurations** with sensible defaults
- **Security best practices** built-in
- **Centralized billing data collection** with cross-project usage reports
- **Multi-resource architecture** supporting instance templates, compute instances, and IAM bindings

#### Available Templates
- **Infrastructure**: Folder, Project, VPC Network, Private Service Access
- **Compute**: Compute Instance, Instance Template, External IP
- **Storage**: Cloud Storage Buckets, BigQuery Datasets
- **Database**: Cloud SQL (MSSQL 2019)
- **Security**: Secrets Manager, IAM Bindings, Firewall Rules

### Security Features
- **Private networking** by default for database resources
- **No hardcoded secrets** - uses Google Secret Manager
- **Least privilege** IAM configurations with dedicated service accounts
- **SSL/TLS enforcement** for all database connections
- **Audit logging** enabled for all projects
- **SSH key encryption** with secure cleanup after use
- **Bucket-level access policies** for GCS resources
- **Pre-commit hooks** for secret detection and code quality
- **Modular script architecture** for security isolation
- **Automated resource cleanup** ensuring no stale permissions

## CI/CD Workflows

### Automated Engine Workflows
- **PR Validation Engine** (`terragrunt-pr-engine.yml`): Validates all infrastructure changes on pull requests
- **Apply Engine** (`terragrunt-apply-engine.yml`): Automatically deploys changes merged to main/develop branches
- **Resource-aware execution**: Respects dependency order and runs parallel operations where possible

### Manual Management Workflows
- **Manage Compute Instance** (`manage-compute-instance.yml`)
  - Deploy/destroy specific compute instances
  - Format: `project/instance` (e.g., `org-dev-01/web-server-01`)
  - Supports comprehensive resource management (VM + IAM bindings)
  
- **Manage SQL Instance** (`manage-sql-instance.yml`)
  - Manage SQL Server instances with specialized handling
  - Format: `project/instance` (e.g., `org-dev-01/sql-server-01`)
  - Handles private networking and SSL configuration
  
- **Upload VM Scripts** (`upload-vm-scripts.yml`)
  - Deploys VM scripts to GCS buckets
  - Automatically triggered after infrastructure deployments
  - Supports force upload option for manual runs

### Workflow Features
- **Comprehensive resource management**: Destroys and recreates all resources (VM + IAM bindings)
- **Environment variable configuration**: Pass parameters via TF_VAR_* variables
- **Automated scheduling**: Cron-based execution for regular operations
- **Detailed reporting**: GitHub step summaries and logs integration
- **Concurrency control**: Prevents overlapping deployments
- **Dependency resolution**: Automatic handling of resource dependencies
- **Rollback capability**: Failed deployments don't leave partial resources

For detailed workflow documentation, see [GitHub Workflows Guide](docs/WORKFLOWS.md).

## Development Best Practices

### Infrastructure Development
1. **Always use Terragrunt commands** - Never use terraform/tofu directly
2. **Check existing patterns** in `_common/templates/` before creating new resources
3. **Use templates** for consistency - don't create resources from scratch
4. **Update module versions** in `_common/common.hcl` centrally
5. **Test changes** with `terragrunt plan` before applying
6. **Follow the established directory structure** for new resources

### Code Quality
1. **Run pre-commit hooks** before committing changes
2. **Use the parse_resource_order.py** script to verify dependencies
3. **Document significant changes** in the appropriate docs/ file

### Workflow Development
1. **Workflows must be in `.github/workflows/`** - don't create elsewhere
2. **Use the project/instance format** for resource identification
3. **Include comprehensive logging** and step summaries
4. **Test workflows** in a development environment first

### Security Practices
1. **Never commit secrets** - use Google Secret Manager
2. **Use dedicated service accounts** with least privilege
3. **Enable audit logging** for all new projects
4. **Review IAM bindings** regularly for unnecessary permissions

## References

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Google Cloud Documentation](https://cloud.google.com/docs)
- [terraform-google-modules](https://github.com/terraform-google-modules) - Official GCP modules
- [Gruntwork Reference Architecture](https://github.com/gruntwork-io/terragrunt-infrastructure-live-example)
