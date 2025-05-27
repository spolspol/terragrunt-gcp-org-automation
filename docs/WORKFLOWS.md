# GitHub Workflows Documentation

This document provides comprehensive information about the GitHub Actions workflows that manage CI/CD and infrastructure operations for the Terragrunt GCP infrastructure.

## Overview

The repository uses a sophisticated GitHub Actions workflow system that provides both automated infrastructure management and manual operational controls. The system is designed to:

- **Validate infrastructure changes** on pull requests
- **Deploy infrastructure changes** automatically on pushes to main/develop branches
- **Respect dependency order** for resource deployment
- **Provide parallel execution** where possible
- **Fail fast** to prevent cascading issues
- **Provide detailed reporting** for each operation
- **Support manual infrastructure operations** for specific resources

## Workflow Architecture

### Three-Tier System

The workflow system operates on three tiers:

1. **Automatic Engine Workflows** - Handle automated CI/CD for infrastructure changes
2. **Manual Management Workflows** - Provide controlled operations for specific resources
3. **Reusable Component Workflows** - Shared components used by other workflows

## Automatic Engine Workflows

These workflows handle the automated CI/CD pipeline for infrastructure changes.

### Core Engine Workflows

| Workflow | Purpose | Trigger | File |
|----------|---------|---------|------|
| **Validation Engine** | Validate changes before merge | `pull_request` | `terragrunt-pr-engine.yml` |
| **Deployment Engine** | Deploy infrastructure changes | `push` | `terragrunt-apply-engine.yml` |

### Supported Resource Types

The engine workflows support the following GCP resource types:

| Resource Type | Description | Template Path | Example Paths |
|---------------|-------------|---------------|---------------|
| **📁 Folder** | GCP organizational folders | `_common/templates/folder.hcl` | `live/**/folder/` |
| **📦 Project** | GCP projects | `_common/templates/project.hcl` | `live/**/project/` |
| **🌐 VPC Network** | Virtual Private Cloud networks | `_common/templates/network.hcl` | `live/**/*-vpc-network/`, `live/**/vpc-network/` |
| **🌍 External IP** | Static external IP addresses | `_common/templates/external_ip.hcl` | `live/**/external-ips/*/` |
| **🔥 Firewall Rules** | VPC firewall rules | `_common/templates/firewall_rules.hcl` | `live/**/firewall-rules/*/` |
| **🔗 Private Service Access** | Private service connections | `_common/templates/private_service_access.hcl` | `live/**/*-psa/` |
| **🪣 Buckets** | Cloud Storage buckets | `_common/templates/cloud_storage.hcl` | `live/**/buckets/*/` |
| **🔐 Secrets** | Secret Manager secrets | `_common/templates/secret_manager.hcl` | `live/**/secrets/*/` |
| **📊 BigQuery** | BigQuery datasets | `_common/templates/bigquery.hcl` | `live/**/bigquery/*/` |
| **🗄️ Cloud SQL** | Cloud SQL databases | `_common/templates/cloud_sql.hcl` | `live/**/cloud-sql/*/` |
| **🚀 Instance Templates** | Compute Engine templates | `_common/templates/instance_template.hcl` | `live/**/compute/*/` |
| **💻 Compute Instances** | Virtual machine instances | `_common/templates/compute_instance.hcl` | `live/**/compute/*/vm/` |

### Execution Order

The engine workflows follow this dependency-aware execution order:

```
📁 folder
└── 📦 project
    ├── 🌐 vpc-network
    │   ├── 🌍 external-ip
    │   ├── 🔥 firewall-rules
    │   ├── 🔗 private-service-access
    │   │   └── 🗄️ cloud-sql
    │   └── 🚀 instance-templates
    │       └── 💻 compute
    ├── 🪣 buckets
    ├── 🔐 secrets
    └── 📊 bigquery
```

**Step-by-Step Execution:**

1. **Step 1**: 📁 Folders - Foundation organizational structure
2. **Step 2**: 📦 Projects - GCP projects that depend on folders
3. **Step 3**: 🌐 VPC Networks + 🔐 Secrets + 🪣 Buckets + 📊 BigQuery - Run in parallel after projects
4. **Step 4**: 🌍 External IPs + 🔥 Firewall Rules + 🔗 Private Service Access + 🚀 Instance Templates - Run in parallel after VPC
5. **Step 5**: 🗄️ Cloud SQL - Database instances that depend on private service access
6. **Step 6**: 💻 Compute Instances - Virtual machines that depend on instance templates

### Engine Workflow Features

#### Change Detection
- **File-based detection** using git diff
- **Template change handling** - if common templates change, all resources of that type are processed
- **Dependency-aware** - understands relationships between resource types
- **Example resource filtering** - automatically excludes resources with certain patterns

#### Parallel Execution
- **Step 3** resources run in parallel (VPC Networks, Secrets, Buckets, BigQuery)
- **Step 4** resources run in parallel after VPC dependencies are met
- **Steps 5 and 6** run sequentially based on specific dependencies
- **Execution stops** at the first failure to prevent cascading issues

#### Example Resource Filtering

Certain resources may be automatically excluded from CI/CD operations based on naming patterns:

**Example Excluded Resources:**
- Test or temporary resources
- Resources with specific prefixes

## Manual Management Workflows

These workflows provide controlled operations for specific infrastructure resources that require manual intervention.

### Available Management Workflows

| Workflow | Purpose | Resources | Input Format |
|----------|---------|-----------|--------------|
| **Manage Compute Instance** | Apply/destroy specific VM instances | Compute Engine VMs | `project/instance` format |
| **Manage SQL Instance** | Apply/destroy SQL Server instances | Compute Engine SQL VMs | `project/instance` format |
| **Upload VM Scripts** | Upload VM scripts to GCS buckets | VM script files | Automatic/Manual trigger |

### Compute Instance Management

**File**: `manage-compute-instance.yml`
**Trigger**: Manual (`workflow_dispatch`)

**Supported Instances**:
- `dev-01/web-server-01`
- `dev-01/app-server-01`

**Operations**:
- Apply (deploy/update instance)
- Destroy (with confirmation required)

**Features**:
- Project/instance format validation
- Destroy confirmation requirement
- Concurrency protection
- Detailed execution reporting

### SQL Instance Management

**File**: `manage-sql-instance.yml`
**Trigger**: Manual (`workflow_dispatch`)

**Supported Instances**:
- `data-staging/sql-server-01`

**Operations**:
- Apply (deploy/update SQL Server)
- Destroy (no confirmation required for SQL instances)

**Features**:
- Project/instance format validation
- Automatic instance path detection
- Concurrency protection
- SQL Server specific optimizations


### VM Scripts Upload

**File**: `upload-vm-scripts.yml`
**Trigger**: Automatic (`push`) or Manual (`workflow_dispatch`)

**Triggering Events**:
- Automatically when VM scripts are pushed to main branch
- Manually with optional force upload flag

**Operations**:
- Detect changes in VM script files
- Discover vm-scripts buckets in target projects
- Upload scripts to appropriate VM type folders
- Verify successful uploads

**Features**:
- Automatic trigger on script changes (`live/**/compute/*/scripts/*.sh`)
- Independent of infrastructure deployments
- Force upload option for manual runs
- Change detection for efficient uploads
- Support for multiple VM types and projects
- Comprehensive verification and reporting

## Reusable Component Workflows

These workflows provide shared functionality used by other workflows.

### Core Reusable Workflows

| Workflow | Purpose | Used By | File |
|----------|---------|---------|------|
| **Common Environment Variables** | Centralized environment configuration | All workflows | `common-env.yml` |
| **Terragrunt Unified** | Core terragrunt operations engine | Engine workflows | `terragrunt-reusable.yaml` |

### Common Environment Variables

**File**: `common-env.yml`
**Type**: Reusable workflow (`workflow_call`)

**Provides**:
```yaml
outputs:
  terragrunt_version: "0.80.2"
  tofu_version: "1.9.1"
  gcp_project_id: "org-test-dev"
  gcp_region: "europe-west2"
  tg_experiment_mode: "true"
  tg_non_interactive: "true"
  tg_backend_bootstrap: "false"
```

### Terragrunt Unified

**File**: `terragrunt-reusable.yaml`
**Type**: Reusable workflow (`workflow_call`)

**Capabilities**:
- **Dual mode operation**: validate or apply
- **Multi-resource support**: handles various resource types
- **Path-based processing**: JSON array configuration
- **Exclusion support**: filters out deleted/example resources
- **Rich reporting**: GitHub step summaries and PR comments
- **Error handling**: comprehensive error reporting and debugging

**Input Parameters**:
```yaml
inputs:
  mode: "validate" | "apply"
  resource_type: "vpc-network" | "compute" | etc.
  resource_paths: JSON array of path patterns
  template_path: Common template path
  resource_emoji: Display emoji
  excluded_resources: JSON array of excluded paths
```

## Usage Patterns

### Automated Infrastructure Changes

#### Single Resource Changes
1. **Create a PR** with your infrastructure changes
2. **Validation Engine triggers** automatically
3. **Review validation results** in PR comments
4. **Merge the PR** if validation passes
5. **Deployment Engine** applies changes automatically

#### Multi-Resource Changes
1. **Create a PR** with changes affecting multiple resource types
2. **Validation Engine** orchestrates validation in dependency order
3. **Review comprehensive validation results** with dependency analysis
4. **Merge the PR** if all validations pass
5. **Deployment Engine** deploys all changes in correct order

#### Template Changes
1. **Modify common templates** in `_common/templates/`
2. **All resources using that template** are automatically included
3. **Engine workflows** handle comprehensive validation and deployment
4. **Coordinated processing** across all affected resources

### Manual Operations

#### Compute Instance Management
```
Workflow: Manage Compute Instance
├── Select Instance: dev-01/web-server-01 | dev-01/app-server-01
├── Select Action: apply | destroy
├── Confirm Destroy: "DESTROY" (if destroying)
└── Execute Operation
```

#### SQL Server Management
```
Workflow: Manage SQL Instance
├── Select Instance: data-staging/sql-server-01
├── Select Action: apply | destroy
└── Execute Operation (no confirmation needed)
```

#### VM Scripts Upload
```
Workflow: Upload VM Scripts
├── Trigger: Automatic (on script push) | Manual
├── Check Script Changes
├── Discover VM Scripts Buckets
├── Upload Scripts to GCS (per VM type)
└── Verify Uploads
```

## Workflow Security and Safety

### Safety Features

#### Automated Workflows
- **Example resource filtering** prevents deployment of demonstration configurations
- **Dependency validation** ensures proper resource ordering
- **Failure isolation** stops execution at first failure
- **Comprehensive logging** for audit trails

#### Manual Workflows
- **Destroy confirmation** required for compute instances
- **Input validation** for all manual selections
- **Concurrency protection** prevents conflicting operations
- **Project/instance format validation** ensures correct targeting

### Security Features
- **Service account authentication** with minimal required permissions
- **Secret management** through GitHub secrets
- **Environment protection rules** for production deployments
- **Audit trails** for all infrastructure operations

## Monitoring and Troubleshooting

### Monitoring Workflows

#### GitHub Actions Interface
- **Actions tab** shows all workflow runs with status
- **Workflow summaries** provide high-level execution overview
- **Step details** offer granular logging and error information
- **Artifacts** contain plan outputs and dependency information

#### Workflow-Specific Monitoring

**Engine Workflows**:
- PR comments with validation results
- Commit comments with deployment status
- Dependency trees and execution order visualization

**Management Workflows**:
- Instance status tracking
- GCP Console integration links
- Operation result summaries

### Common Issues and Solutions

#### Engine Workflow Issues

**1. Workflow Not Triggering**
- **Cause**: Path patterns don't match changed files
- **Solution**: Review path patterns in workflow triggers
- **Debug**: Check git diff output matches expected patterns

**2. Dependency Failures**
- **Cause**: Required dependencies not available or deployed
- **Solution**: Check dependency order and mock outputs
- **Debug**: Review dependency validation in workflow logs

**3. Resource Detection Issues**
- **Cause**: Changed files not detected by resource patterns
- **Solution**: Verify resource patterns in detection logic
- **Debug**: Examine change detection step outputs

#### Management Workflow Issues

**1. Instance Not Found**
- **Cause**: Instance path validation failure
- **Solution**: Verify instance exists at expected path
- **Debug**: Check find command patterns and project matching

**2. Input Validation Failures**
- **Cause**: Invalid project/instance format or non-existent resources
- **Solution**: Use correct format and verify instance availability
- **Debug**: Review validation step logs for specific errors

**3. Concurrency Conflicts**
- **Cause**: Multiple workflows targeting same resource
- **Solution**: Wait for running workflows to complete
- **Debug**: Check workflow run queue and concurrency groups

#### VM Scripts Upload Issues

**1. Scripts Not Uploading**
- **Cause**: No script changes detected in push event
- **Solution**: Use manual trigger with force upload option
- **Debug**: Check workflow summary for detection results

**2. Bucket Not Found**
- **Cause**: VM scripts bucket doesn't exist in target project
- **Solution**: Ensure vm-scripts bucket is deployed first
- **Debug**: Check bucket discovery logs in workflow

**3. Upload Failures**
- **Cause**: Permission issues or network problems
- **Solution**: Verify service account has storage permissions
- **Debug**: Check gsutil error messages in upload step

### Debugging Workflows

#### Enable Debug Logging
```yaml
env:
  TOFU_LOG: DEBUG
  ACTIONS_STEP_DEBUG: true
  ACTIONS_RUNNER_DEBUG: true
```

#### Local Testing
```bash
# Install act for local workflow testing
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Test validation workflow locally
act pull_request --workflows .github/workflows/terragrunt-pr-engine.yml

# Test manual workflow locally
act workflow_dispatch --workflows .github/workflows/manage-compute-instance.yml
```

## Configuration

### Required GitHub Secrets

| Secret | Description | Used By |
|--------|-------------|---------|
| `TF_GOOGLE_CREDENTIALS` | GCP service account credentials | All workflows |
| `GCP_SA_KEY` | GCP service account key for VM scripts | Upload VM Scripts workflow |

### Environment Configuration

Environment variables are centrally managed through `common-env.yml`:

```yaml
# Core versions
TERRAGRUNT_VERSION: "0.80.2"
TOFU_VERSION: "1.9.1"

# GCP configuration
GCP_PROJECT_ID: "org-test-dev"
GCP_REGION: "europe-west2"

# Terragrunt configuration
TG_EXPERIMENT_MODE: "true"
TG_NON_INTERACTIVE: "true"
TG_BACKEND_BOOTSTRAP: "false"
```

### Customization

#### Adding New Resource Types
1. **Update engine workflows** with new resource patterns
2. **Add resource detection logic** in change detection
3. **Create reusable templates** if needed
4. **Update dependency order** if required

#### Modifying Manual Workflows
1. **Add new instance options** to workflow inputs
2. **Update validation logic** for new instances
3. **Modify path detection** patterns as needed
4. **Update help text** and error messages

#### Adjusting Execution Order
1. **Modify dependency conditions** in engine workflows
2. **Update step organization** for clarity
3. **Adjust parallel execution** groups as needed
4. **Test with multi-resource changes**

## Best Practices

### Infrastructure Development
1. **Test changes in feature branches** before merging
2. **Use small, focused changes** when possible
3. **Review plan outputs** carefully in PR validation
4. **Monitor deployments** through workflow summaries

### Manual Operations
1. **Use manual workflows** for one-off operations only
2. **Verify instance selection** before executing
3. **Monitor execution progress** through workflow logs
4. **Check GCP Console** to verify results

### Workflow Maintenance
1. **Keep reusable workflows** up to date
2. **Monitor for deprecated** GitHub Actions features
3. **Update environment versions** regularly
4. **Review and clean up** old workflow runs and artifacts

### Security
1. **Rotate service account keys** regularly
2. **Review workflow permissions** periodically
3. **Monitor for sensitive data** in workflow logs
4. **Use environment protection rules** for critical resources

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Workflow Security](https://docs.github.com/en/actions/security-guides)
- [Environment Protection Rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Terragrunt CLI Documentation](https://terragrunt.gruntwork.io/docs/reference/cli-options/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
