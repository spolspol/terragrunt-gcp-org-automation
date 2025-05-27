# Compute Instance Template

This document provides detailed information about the Compute Instance template and multi-VM architecture available in the Terragrunt GCP infrastructure.

## Overview

The Compute Instance template (`_common/templates/compute_instance.hcl`) provides a standardized approach to deploying Google Cloud compute instances using the [terraform-google-vm](https://github.com/terraform-google-modules/terraform-google-vm) module's `compute_instance` submodule. This approach uses instance templates to create individual VMs, providing better consistency, reusability, and management.

## Architecture

The architecture follows this pattern:

1. **Instance Template**: Creates a reusable instance template using the `instance_template` submodule
2. **Compute Instance**: Uses the instance template to create actual VM instances using the `compute_instance` submodule

Benefits:
- **Consistency**: All instances created from the same template have identical configuration
- **Reusability**: Templates can be reused to create multiple instances
- **Manageability**: Changes to the template automatically apply to new instances
- **Best Practices**: Leverages Google's official terraform-google-vm module

## Directory Structure

```
compute/
├── compute.hcl                    # Common compute configuration for all VMs
├── vm-name-01/
│   ├── terragrunt.hcl             # Instance template configuration
│   ├── iam-bindings/
│   │   └── terragrunt.hcl         # IAM bindings for instance service account
│   └── vm/
│       └── terragrunt.hcl         # Compute instance (uses template)
└── vm-name-02/
    ├── terragrunt.hcl             # Instance template configuration
    ├── iam-bindings/
    │   └── terragrunt.hcl         # IAM bindings for instance service account
    └── vm/
        └── terragrunt.hcl         # Compute instance (uses template)
```

## Common Configuration (`compute.hcl`)

The `compute.hcl` file provides shared configuration for all compute instances:

- **Common Dependencies**: Standardized paths to VPC network, project, and secrets
- **Mock Outputs**: Consistent mock data for dependency testing
- **Network Configuration**: Shared subnet selection and access configuration
- **Service Account Settings**: Default scopes and configuration
- **Metadata**: Common metadata like OS Login settings
- **Labels**: Standard labels applied to all compute instances

## Environment-aware Configuration

The templates automatically apply different settings based on the environment:

| Feature | Production | Non-Production |
|---------|------------|----------------|
| Machine Type | e2-standard-2 | e2-micro |
| Disk Type | pd-ssd | pd-standard |
| Disk Size | 50 GB | 20 GB |
| Preemptibility | No | Yes |
| Deletion Protection | Yes | No |
| Network Tier | PREMIUM | STANDARD |

## Configuration Options

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `project_id` | The GCP project ID where the instance will be created |
| `name_prefix` | The name prefix for the instance template |
| `hostname` | The hostname of the compute instance |
| `zone` | The zone where the instance will be deployed |
| `network` | The network to attach to the instance |
| `subnetwork` | The subnetwork to attach to the instance |
| `service_account.email` | Service account email to assign to the instance |
| `instance_template` | The instance template self-link (for compute instances) |

## Usage

### Creating a New VM

1. **Create a new subfolder** under `compute/` with a descriptive name
2. **Create the instance template** by creating `terragrunt.hcl` 
3. **Create IAM bindings** (optional but recommended) by creating `iam-bindings/terragrunt.hcl`
4. **Create the compute instance** by creating `vm/terragrunt.hcl` that depends on the instance template
5. **Include the common compute configuration** by adding the `compute_common` include block

### Instance Template Example

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "instance_template" {
  path = "${get_terragrunt_dir()}/path/to/_common/templates/instance_template.hcl"
}

include "compute_common" {
  path = find_in_parent_folders("compute.hcl")
}

locals {
  merged_vars = merge(
    read_terragrunt_config(find_in_parent_folders("account.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("env.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("project.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals
  )
  
  selected_env_config = lookup(local.merged_vars.compute_instance_settings, local.merged_vars.environment_type, {})
}

inputs = merge(
  read_terragrunt_config("path/to/_common/templates/instance_template.hcl").inputs,
  local.merged_vars,
  local.selected_env_config,
  {
    # Basic template configuration
    name_prefix = "${local.merged_vars.name_prefix}-${local.merged_vars.project}-vm-name"
    project_id  = "${local.merged_vars.name_prefix}-${local.merged_vars.project_id}"
    
    # Network configuration
    network            = "${local.merged_vars.name_prefix}-${local.merged_vars.project}-vpc-01"
    subnetwork         = "${local.merged_vars.name_prefix}-${local.merged_vars.project}-subnet-01"
    subnetwork_project = "${local.merged_vars.name_prefix}-${local.merged_vars.project_id}"
    
    # Boot disk configuration
    source_image_family  = "debian-12"
    source_image_project = "debian-cloud"
    
    # Service account configuration (choose one approach)
    
    # Option 1: Create dedicated service account (RECOMMENDED)
    create_service_account = true
    service_account = null
    
    # Option 2: Use shared project service account (legacy)
    # service_account = {
    #   email  = local.merged_vars.project_service_account
    #   scopes = local.selected_env_config.scopes
    # }
    
    # Custom startup script with VM scripts download
    metadata = {
      startup-script = <<-EOT
        #!/bin/bash
        set -e
        
        # Download VM scripts from GCS bucket (if applicable)
        VM_TYPE="vm-name-01"  # Match the directory name
        SCRIPTS_BUCKET="${local.merged_vars.name_prefix}-${local.merged_vars.project_name}-vm-scripts"
        SCRIPTS_DIR="/opt/scripts"
        
        # Create scripts directory
        mkdir -p $SCRIPTS_DIR
        
        # Download scripts from bucket if exists
        if gsutil ls gs://$SCRIPTS_BUCKET/$VM_TYPE/ 2>/dev/null; then
          echo "Downloading scripts from gs://$SCRIPTS_BUCKET/$VM_TYPE/"
          gsutil -m cp -r gs://$SCRIPTS_BUCKET/$VM_TYPE/* $SCRIPTS_DIR/
          chmod +x $SCRIPTS_DIR/*.sh
          
          # Execute bootstrap script if exists
          if [ -f "$SCRIPTS_DIR/bootstrap.sh" ]; then
            echo "Executing bootstrap script..."
            $SCRIPTS_DIR/bootstrap.sh
          fi
        else
          echo "No scripts bucket found or accessible"
        fi
        
        # Continue with regular startup tasks
        apt-get update
        apt-get install -y nginx
        systemctl enable nginx
        systemctl start nginx
        
        echo "VM setup complete"
      EOT
    }
    
    # Resource Labels
    labels = merge(
      {
        instance = "vm-name"
        purpose  = "vm-purpose"
      },
      local.merged_vars.org_labels,
      local.merged_vars.env_labels,
      local.merged_vars.project_labels
    )
  }
)
```

### Compute Instance Example

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "compute_template" {
  path = "path/to/_common/templates/compute_instance.hcl"
}

include "compute_common" {
  path = find_in_parent_folders("compute.hcl")
}

dependency "instance_template" {
  config_path = "./instance-template"
  mock_outputs = {
    self_link = "projects/mock-project/global/instanceTemplates/mock-template"
    name = "mock-template"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "vpc-network" {
  config_path = "../../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock-project/global/networks/default"
    subnets_self_links = ["projects/mock-project/regions/region/subnetworks/default"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "project" {
  config_path = "../../project"
  mock_outputs = {
    project_id = "mock-project-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

locals {
  merged_vars = merge(
    read_terragrunt_config(find_in_parent_folders("account.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("env.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("project.hcl")).locals,
    read_terragrunt_config(find_in_parent_folders("_common/common.hcl")).locals
  )
  
  selected_env_config = lookup(local.merged_vars.compute_instance_settings, local.merged_vars.environment_type, {})
}

inputs = merge(
  read_terragrunt_config("path/to/_common/templates/compute_instance.hcl").inputs,
  local.merged_vars,
  local.selected_env_config,
  {
    # Basic instance configuration
    hostname   = "${local.merged_vars.name_prefix}-${local.merged_vars.project}-vm-name"
    project_id = dependency.project.outputs.project_id
    zone       = "${local.merged_vars.region}-a"
    
    # Instance template dependency
    instance_template = dependency.instance_template.outputs.self_link
    
    # Network configuration
    network            = dependency.vpc-network.outputs.network_self_link
    subnetwork         = dependency.vpc-network.outputs.subnets_self_links[0]
    subnetwork_project = dependency.project.outputs.project_id
    
    # Service account configuration (choose one approach)
    
    # Option 1: Create dedicated service account (RECOMMENDED)
    create_service_account = true
    service_account = null
    
    # Option 2: Use shared project service account (legacy)
    # service_account = {
    #   email  = local.merged_vars.project_service_account
    #   scopes = local.selected_env_config.scopes
    # }
    
    # Resource Labels
    labels = merge(
      {
        instance = "vm-name"
        purpose  = "vm-purpose"
      },
      local.merged_vars.org_labels,
      local.merged_vars.env_labels,
      local.merged_vars.project_labels
    )
    
    # Number of instances to create
    num_instances = 1
  }
)
```

## Service Account Configuration

### Dedicated Service Accounts (Recommended)

For enhanced security, create a dedicated service account for each instance:

```hcl
inputs = {
  # Create a dedicated service account for this instance
  create_service_account = true
  
  # Service account must be null for the module to create a new one
  service_account = null
  
  # Other configuration...
}
```

Benefits:
- **Least Privilege**: Grant only necessary permissions to each instance
- **Security Isolation**: Compromised instance doesn't affect other resources
- **Auditability**: Clear tracking of which instance performed which actions
- **Compliance**: Better alignment with security best practices

### Shared Project Service Account (Legacy)

The legacy approach uses a shared project service account:

```hcl
inputs = {
  service_account = {
    email  = dependency.project.outputs.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  
  # Other configuration...
}
```

**Note**: This approach is discouraged for production workloads due to security concerns.

## IAM Bindings Integration

When using dedicated service accounts, create IAM bindings to grant specific permissions:

### Example IAM Bindings Configuration

Create `iam-bindings/terragrunt.hcl`:

```hcl
include "iam_template" {
  path = "${get_repo_root()}/_common/templates/iam_bindings.hcl"
}

dependency "instance_template" {
  config_path = "../"
  mock_outputs = {
    service_account_info = {
      email = "mock-service-account@mock-project-id.iam.gserviceaccount.com"
    }
  }
}

inputs = {
  projects = [dependency.project.outputs.project_id]
  mode     = "additive"

  bindings = {
    # Grant access to secrets
    "roles/secretmanager.secretAccessor" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
    
    # Grant storage access
    "roles/storage.objectViewer" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
    
    # Grant monitoring and logging permissions
    "roles/logging.logWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
    
    "roles/monitoring.metricWriter" = [
      "serviceAccount:${dependency.instance_template.outputs.service_account_info.email}"
    ]
  }
}
```

For detailed information on IAM bindings, see [IAM Bindings Template Guide](IAM_BINDINGS_TEMPLATE.md).

## Advanced Usage

### Rclone-based Cloud-to-Cloud Architectures

For ephemeral workers that perform cloud-to-cloud data transfers, consider using rclone for direct synchronization without local storage:

#### Example: Web Server Instance

The web server (`web-server-01`) demonstrates this pattern:

```hcl
# Key characteristics:
- Standard disk size for web content and logs
- Nginx or Apache web server configuration
- Persistent instance for serving requests
- Dedicated service account with specific IAM bindings

# Architecture benefits:
- Scalable web serving capabilities
- Load balancer integration ready
- Security through IAM and firewall rules
- Easy deployment via startup scripts
```

**Implementation Pattern:**
1. Configure web server software via startup script
2. Set up SSL/TLS certificates for HTTPS
3. Configure health checks for load balancing
4. Implement logging to Cloud Logging
5. Set up monitoring and alerting

For a complete implementation example, see the web server configurations in:
`/live/non-production/development/dev-01/europe-west2/compute/linux-server-01/`

### Creating Multiple Instances

```hcl
inputs = merge(
  # ... other configuration ...
  {
    # Create multiple instances from the same template
    num_instances = 3
    
    # Optionally provide static IPs for each instance
    static_ips = ["10.10.0.10", "10.10.0.11", "10.10.0.12"]
  }
)
```

### Adding Additional Disks

```hcl
inputs = merge(
  # ... other configuration ...
  {
    # Attach additional disks
    additional_disks = [
      {
        source      = "projects/${project_id}/zones/${zone}/disks/data-disk"
        device_name = "data-disk"
        mode        = "READ_WRITE"
      }
    ]
  }
)
```

## Best Practices

1. **Use Instance Templates** - Always create an instance template before creating compute instances
2. **Use Common Configuration** - Always include the `compute_common` configuration to leverage shared settings
3. **Use Dependencies** - Always use dependencies for VPC network, project, and instance template resources
4. **Environment Awareness** - Leverage the environment-specific configurations from `compute_instance_settings`
5. **Consistent Naming** - Use the naming pattern `${name_prefix}-${project}-${instance_name}`
6. **Security** - Always connect VMs to the VPC network, never use default networks
7. **Resource Labels** - Use comprehensive labeling for cost allocation and resource management
8. **Script Management** - Use centralized VM scripts bucket for maintainable script deployment
9. **Modular Scripts** - Organize scripts into logical modules for easier maintenance

## VM Scripts Integration

### Overview

The compute template supports automatic download and execution of scripts from a centralized GCS bucket. This enables:
- **Centralized Management**: All VM scripts stored in one location
- **Automatic Updates**: Scripts automatically synchronized via GitHub Actions
- **Modular Architecture**: Scripts organized by VM type for clarity
- **Version Control**: Script changes tracked in Git repository

### Script Organization

Scripts are organized in the repository and bucket by VM type:
```
live/account/env/project/region/compute/
├── web-server-01/
│   └── scripts/
│       ├── bootstrap.sh           # Main entry point
│       ├── system-setup.sh        # System dependencies
│       └── application-logic.sh   # Application-specific logic
└── app-server-01/
    └── scripts/
        ├── bootstrap.sh
        └── nginx-setup.sh
```

### Startup Script Pattern

The following pattern downloads and executes scripts from the vm-scripts bucket:

```bash
#!/bin/bash
set -e

# Configuration
VM_TYPE="$(basename $(dirname $(dirname $0)))"  # Auto-detect from path
SCRIPTS_BUCKET="${name_prefix}-${project_name}-vm-scripts"
SCRIPTS_DIR="/opt/scripts"

# Download scripts
mkdir -p $SCRIPTS_DIR
if gsutil ls gs://$SCRIPTS_BUCKET/$VM_TYPE/ 2>/dev/null; then
  gsutil -m cp -r gs://$SCRIPTS_BUCKET/$VM_TYPE/* $SCRIPTS_DIR/
  chmod +x $SCRIPTS_DIR/*.sh
  
  # Execute bootstrap
  if [ -f "$SCRIPTS_DIR/bootstrap.sh" ]; then
    $SCRIPTS_DIR/bootstrap.sh
  fi
fi
```

### Script Upload Workflow

1. **Automatic Upload**: Scripts are automatically uploaded when:
   - Changes are pushed to main branch
   - Infrastructure deployment completes successfully

2. **Manual Upload**: Force upload all scripts:
   ```bash
   gh workflow run upload-vm-scripts.yml --field force_upload=true
   ```

### Best Practices for VM Scripts

1. **Bootstrap Pattern**: Always use a `bootstrap.sh` as the main entry point
2. **Error Handling**: Include comprehensive error handling and logging
3. **Idempotency**: Make scripts safe to run multiple times
4. **Modularity**: Break complex logic into separate script files
5. **Environment Variables**: Pass configuration via environment variables
6. **Progress Logging**: Log progress for debugging and monitoring

## Deployment Order

1. **Project** → Creates the GCP project
2. **VPC Network** → Creates the network infrastructure
3. **Secrets** → Creates any required secrets
4. **Buckets** → Creates storage buckets including vm-scripts
5. **Instance Template** → Creates the instance template and service account
6. **IAM Bindings** → Grants permissions to the service account (if using dedicated service accounts)
7. **Compute Instance** → Creates the actual VM using the template
8. **Script Upload** → VM scripts automatically uploaded to bucket

## Troubleshooting

### Common Issues

1. **Instance Template Not Found**
   - Ensure the instance template is created before the compute instance
   - Check the dependency configuration in the compute instance

2. **Source Image Configuration Issues**
   - Use separate `source_image_family` and `source_image_project` parameters

3. **Subnetwork Project Mismatch**
   - Add `subnetwork_project` to both instance template and compute instance configurations

4. **Service Account Issues**
   - **Using dedicated service accounts**: Ensure `create_service_account = true` and `service_account = null`
   - **Using project service accounts**: Check the `project_service_account` value in your `project.hcl` file
   - **IAM bindings errors**: Verify the instance template is deployed before IAM bindings

5. **Permission Denied Errors**
   - Check that IAM bindings have been applied for dedicated service accounts
   - Verify the service account has the required roles for the instance's function
   - Use `gcloud projects get-iam-policy PROJECT_ID` to check current permissions

6. **Script Download Failures**
   - Verify vm-scripts bucket exists and is accessible
   - Check service account has storage.objectViewer permission
   - Ensure scripts have been uploaded via GitHub Actions workflow
   - Check startup script logs in GCP Console for gsutil errors

7. **Script Execution Failures**
   - Verify scripts have execute permissions (chmod +x)
   - Check script logs in /var/log/ or GCP Console
   - Ensure all script dependencies are installed
   - Verify environment variables are properly set

### Validation Commands

```bash
# List instance templates
gcloud compute instance-templates list --project=PROJECT_ID

# List compute instances
gcloud compute instances list --project=PROJECT_ID

# Describe an instance template
gcloud compute instance-templates describe TEMPLATE_NAME --project=PROJECT_ID

# List service accounts (for dedicated service accounts)
gcloud iam service-accounts list --project=PROJECT_ID

# Check IAM bindings
gcloud projects get-iam-policy PROJECT_ID
```

## Module Outputs

### Instance Template Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `self_link` | Self-link of the instance template | `"projects/project/global/instanceTemplates/template-name"` |
| `name` | Name of the instance template | `"vm-template-name"` |
| `service_account_info` | Service account information (when `create_service_account = true`) | `{email = "...", id = "...", member = "..."}` |

### Compute Instance Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `instances_self_links` | Self-links of the created instances | `["projects/project/zones/zone/instances/instance-name"]` |
| `instances_details` | Detailed information about instances | Complex object with instance details |
| `available_zones` | Available zones for the instances | `["region-a", "region-b"]` |

## References

- [terraform-google-vm module](https://github.com/terraform-google-modules/terraform-google-vm)
- [Google Cloud Instance Templates documentation](https://cloud.google.com/compute/docs/instance-templates)
- [Google Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/)
