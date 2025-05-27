# Using OpenTofu with Terragrunt GCP Infrastructure

## Overview

This project uses [OpenTofu](https://opentofu.org/) instead of Terraform as the infrastructure as code tool. OpenTofu is a community-driven, open source fork of Terraform that maintains compatibility with Terraform while focusing on long-term stability and community governance.

## Why OpenTofu?

- **Open Governance**: OpenTofu is governed by the Linux Foundation with a community-focused approach
- **Compatibility**: OpenTofu maintains compatibility with Terraform configurations and providers
- **Long-term Stability**: Less subject to licensing or commercial changes
- **Community Support**: Active community development and support

## Installation

### MacOS

Using Homebrew:
```bash
brew install opentofu
```

### Linux

Using the installation script:
```bash
curl -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method package
```

Manual installation:
```bash
curl -fsSL https://github.com/opentofu/opentofu/releases/download/v1.6.0/tofu_1.6.0_linux_amd64.zip -o opentofu.zip
unzip opentofu.zip
chmod +x tofu
sudo mv tofu /usr/local/bin/
```

## Verify Installation

```bash
tofu version
```

You should see output like:
```
OpenTofu v1.6.0
```

## Project Configuration

This project is already configured to use OpenTofu instead of Terraform:

1. The `root.hcl` file specifies OpenTofu as the binary:
   ```hcl
   terraform {
     terraform_binary = "tofu"
     required_version = ">= 1.6.0"
   }
   ```

2. Provider configurations have been updated to be compatible with OpenTofu.

## Environment Variables

OpenTofu uses different environment variables than Terraform:

| Terraform Variable | OpenTofu Equivalent |
|-------------------|---------------------|
| `TF_LOG` | `TOFU_LOG` |
| `TF_VAR_name` | `TOFU_VAR_name` |
| `TF_CLI_ARGS` | `TOFU_CLI_ARGS` |

Example:
```bash
# Set log level
export TOFU_LOG=DEBUG

# Set variables
export TOFU_VAR_project_id="my-project"
```

## GCP Authentication

Proper authentication is essential for working with GCP resources. This project supports various authentication methods, with service accounts being recommended for automation and local development.

For a comprehensive guide on setting up GCP authentication for this project, please refer to our detailed [GCP Authentication Guide](GCP_AUTHENTICATION.md).

### Quick Setup

1. **Create a service account** with appropriate permissions
2. **Generate a JSON key file** for the service account
3. **Set the environment variable**:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your-project-credentials.json"
   ```
4. **Verify authentication**:
   ```bash
   gcloud auth application-default print-access-token
   ```

The provider configuration in root.hcl is already set up to use these credentials automatically.

## Using Terragrunt with OpenTofu

Terragrunt commands remain the same, as Terragrunt automatically uses the configured OpenTofu binary:

```bash
# Initialize
terragrunt init

# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy
terragrunt destroy

# Apply all modules in a directory
terragrunt run-all apply
```

## Remote State Management

This project stores state in a GCS bucket. The remote state configuration in `root.hcl` works with OpenTofu without modification:

```hcl
remote_state {
  backend = "gcs"
  config = {
    bucket   = "my-terragrunt-state-bucket"
    prefix   = "${path_relative_to_include()}"
    project  = "my-gcp-project-id"
    location = "us-central1"
  }
}
```

## State Migration (From Terraform)

If migrating from Terraform to OpenTofu:

1. **Backup your Terraform state**:
   ```bash
   terragrunt state pull > terraform.tfstate.backup
   ```

2. **Reinitialize with OpenTofu**:
   ```bash
   terragrunt init
   ```

3. **Verify state was maintained**:
   ```bash
   terragrunt state list
   ```

## Common Issues and Troubleshooting

### Provider Compatibility

OpenTofu uses the same providers as Terraform. If you encounter provider issues:

1. Remove `.terragrunt-cache` and `.terraform` directories
2. Run `terragrunt init` again

### Version Constraints

If you see version constraint errors:

1. Update `root.hcl` to specify a supported OpenTofu version
2. Remove version constraints from provider blocks

### Authentication Issues

For GCP authentication issues:

```bash
# Verify authentication
gcloud auth login
gcloud auth application-default login

# Verify project access
gcloud projects describe PROJECT_ID
```

## Best Practices

1. **Use Environment Variables**: Store sensitive information in environment variables
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
   ```

2. **Clear Cache When Switching**: When switching between Terraform and OpenTofu, clear the cache
   ```bash
   rm -rf .terraform .terragrunt-cache
   ```

3. **Version Control**: Make sure `.terragrunt-cache` and local `.terraform` directories are in `.gitignore`

4. **State Locking**: Always use state locking (enabled by default in our configuration)

5. **Plan Before Apply**: Always run `terragrunt plan` before `terragrunt apply`
   ```bash
   terragrunt plan -out=plan.out
   terragrunt apply plan.out
   ```

## Command Reference

| Task | Command |
|------|---------|
| Initialize a module | `terragrunt init` |
| Plan changes | `terragrunt plan` |
| Apply changes | `terragrunt apply` |
| Destroy resources | `terragrunt destroy` |
| List resources in state | `terragrunt state list` |
| View a resource in state | `terragrunt state show RESOURCE` |
| Run commands in all modules | `terragrunt run-all COMMAND` |
| Validate configuration | `terragrunt validate` |
| Format files | `tofu fmt` (not through terragrunt) |

## References

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)
- [OpenTofu GitHub Repository](https://github.com/opentofu/opentofu)
- [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
