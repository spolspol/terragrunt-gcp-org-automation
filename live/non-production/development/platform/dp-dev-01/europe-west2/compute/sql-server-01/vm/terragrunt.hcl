# SQL Server VM Instance Configuration
# Windows Server with SQL Server Standard 2019

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "project" {
  path = find_in_parent_folders("project.hcl")
}

include "region" {
  path = find_in_parent_folders("region.hcl")
}

include "common" {
  path = "${get_repo_root()}/_common/common.hcl"
}

include "compute_config" {
  path = "../../compute.hcl"
}

include "parent_config" {
  path = "../terragrunt.hcl"
}

include "compute_template" {
  path = "${get_repo_root()}/_common/templates/compute_instance.hcl"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config("${get_repo_root()}/_common/common.hcl")
  compute_vars = read_terragrunt_config("../../compute.hcl")
  parent_vars  = read_terragrunt_config("../terragrunt.hcl")

  merged_vars = merge(
    local.account_vars.locals,
    local.env_vars.locals,
    local.project_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )

  # Dynamic path construction
  project_base_path = dirname(dirname(dirname(dirname(get_terragrunt_dir()))))
  vpc_network_path  = "${local.project_base_path}/vpc-network"
  secrets_base_path = "${local.project_base_path}/secrets"

  # VM name from parent directory
  vm_name = local.parent_vars.locals.vm_name
}

dependency "project" {
  config_path                             = find_in_parent_folders("project")
  mock_outputs                            = local.compute_vars.locals.common_mock_outputs.project
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "vpc-network" {
  config_path                             = local.vpc_network_path
  mock_outputs                            = local.compute_vars.locals.common_mock_outputs.vpc_network
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "sql-admin-password" {
  config_path = "${local.secrets_base_path}/sql-server-admin-password"
  mock_outputs = {
    secret_id           = "sql-server-admin-password"
    secret_version_data = "mock-password"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = true
}

inputs = {
  project_id = dependency.project.outputs.project_id
  zone       = "${local.merged_vars.region}-${local.compute_vars.locals.zone_mapping.sql_server}"

  # Instance configuration
  instance_name = "${local.merged_vars.project_name}-${local.vm_name}"
  machine_type  = local.parent_vars.locals.sql_server_config.machine_type

  # Boot disk configuration
  boot_disk = {
    initialize_params = {
      image = "${local.parent_vars.locals.sql_server_config.image_project}/${local.parent_vars.locals.sql_server_config.image_family}"
      size  = local.parent_vars.locals.sql_server_config.disk_size_gb
      type  = local.parent_vars.locals.sql_server_config.disk_type
    }
  }

  # Network configuration
  network_interface = {
    network    = dependency.vpc-network.outputs.network_self_link
    subnetwork = dependency.vpc-network.outputs.subnets_self_links[0]

    # No external IP for SQL Server (access via Cloud NAT)
    access_config = []
  }

  # Service account and scopes
  service_account = {
    email  = dependency.project.outputs.service_account_email
    scopes = local.compute_vars.locals.common_service_account_config.default_scopes
  }

  # Metadata
  metadata = merge(
    local.compute_vars.locals.common_metadata,
    {
      windows-startup-script-ps1 = <<-EOT
        # Windows startup script for SQL Server configuration

        # Enable SQL Server authentication mode
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer" -Name "LoginMode" -Value 2

        # Restart SQL Server service
        Restart-Service -Name MSSQLSERVER -Force

        # Configure Windows Firewall for SQL Server
        New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow
        New-NetFirewallRule -DisplayName "SQL Server Browser" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow

        # Enable Remote Desktop
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

        # Log completion
        Write-EventLog -LogName Application -Source "GCE" -EventID 1000 -EntryType Information -Message "SQL Server startup configuration completed"
      EOT
    }
  )

  # Tags
  tags = concat(
    local.compute_vars.locals.nat_config.nat_tags,
    ["sql-server", "windows", "database"]
  )

  # Labels
  labels = merge(
    local.compute_vars.locals.common_compute_labels,
    {
      os          = "windows"
      application = "sql-server"
      version     = "2019"
      environment = local.merged_vars.environment
    },
    try(local.merged_vars.org_labels, {}),
    try(local.merged_vars.env_labels, {})
  )

  # Allow stopping for updates
  allow_stopping_for_update = true

  # Enable shielded VM features
  shielded_instance_config = {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}
