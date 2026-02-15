# Nginx Web Server Instance Template Configuration
# This creates a compute instance template for a simple web server

# Include the compute instance template configuration
include "instance_template" {
  path = "${get_repo_root()}/_common/templates/instance_template.hcl"
}

# Configuration for the dependency
dependency "vpc-network" {
  config_path = "../../../vpc-network"
  
  mock_outputs = {
    network_name = "mock-network"
    network_id   = "mock-network-id"
  }
  
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Dependency on the vm-scripts bucket
dependency "vm-scripts-bucket" {
  config_path = "../../buckets/vm-scripts"
  
  mock_outputs = {
    names = ["mock-vm-scripts-bucket"]
  }
  
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Dependency on the static-content bucket
dependency "static-content-bucket" {
  config_path = "../../buckets/static-content"
  
  mock_outputs = {
    names = ["mock-static-content-bucket"]
  }
  
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Load account and environment configurations
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  compute_vars = read_terragrunt_config(find_in_parent_folders("compute.hcl", "compute.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("_common/common.hcl"))
  
  environment_type = local.env_vars.locals.environment_type
  
  # Web server specific configuration
  machine_type = local.common_vars.locals.compute_defaults.machine_types[local.environment_type].small
  disk_size    = 10
  
  # Bootstrap script to download and execute setup
  startup_script = templatefile("${get_terragrunt_dir()}/scripts/nginx-bootstrap.sh", {
    project_id     = local.project_vars.locals.project_name
    bucket_name    = try(dependency.vm-scripts-bucket.outputs.names[0], "mock-vm-scripts-bucket")
    instance_name  = "web-server-01"
    region         = local.region_vars.locals.region
    
    # Web server specific variables
    static_content_bucket = try(dependency.static-content-bucket.outputs.names[0], "mock-static-content-bucket")
    ssl_cert_email_secret = "projects/${local.project_vars.locals.project_name}/secrets/ssl-cert-email/versions/latest"
    ssl_domains_secret    = "projects/${local.project_vars.locals.project_name}/secrets/ssl-domains/versions/latest"
  })
}

# Input variables for the module
inputs = {
  name_prefix  = "${local.project_vars.locals.project_name}-web-server-01"
  project_id   = local.project_vars.locals.project_name
  
  network    = dependency.vpc-network.outputs.network_name
  subnetwork = dependency.vpc-network.outputs.subnets["${local.region_vars.locals.region}/${local.project_vars.locals.project_name}-${local.env_vars.locals.environment}-${local.region_vars.locals.region}"].name
  region     = local.region_vars.locals.region
  
  # Machine configuration
  machine_type = local.machine_type
  min_cpu_platform = null
  
  # Service account (will be created by instance template module)
  service_account = {
    email  = ""  # Will be created by module
    scopes = ["cloud-platform"]
  }
  
  # Disk configuration
  disk_size_gb = local.disk_size
  disk_type    = "pd-standard"
  
  # Instance configuration
  enable_shielded_vm = true
  shielded_instance_config = {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
  
  # Simple web server - allow preemptible in non-production
  preemptible        = local.environment_type != "production"
  automatic_restart  = !local.environment_type != "production"
  on_host_maintenance = local.environment_type == "production" ? "MIGRATE" : "TERMINATE"
  
  # Startup script
  startup_script = local.startup_script
  
  # Metadata
  metadata = {
    enable-osconfig         = "TRUE"
    enable-guest-attributes = "TRUE"
    block-project-ssh-keys  = "TRUE"
  }
  
  # Tags for firewall rules
  tags = ["web-server", "http-server", "https-server"]
  
  # Labels
  labels = merge(
    local.account_vars.locals.org_labels,
    local.env_vars.locals.env_labels,
    {
      component = "web-server"
      purpose   = "static-website"
    }
  )
}