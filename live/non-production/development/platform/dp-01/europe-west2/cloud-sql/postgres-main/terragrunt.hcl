# PostgreSQL Cloud SQL for dp-01 data platform

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_sql_postgres_template" {
  path           = "${get_repo_root()}/_common/templates/cloud_sql_postgres.hcl"
  merge_strategy = "deep"
}

dependency "project" {
  config_path = "../../../project"
  mock_outputs = {
    project_id   = "mock-project-id"
    project_name = "mock-project-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "network" {
  config_path = "../../../vpc-network"
  mock_outputs = {
    network_self_link = "projects/mock-project/global/networks/mock-network"
    network_name      = "mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "private_service_access" {
  config_path = "../../networking/private-service-access"
  mock_outputs = {
    peering_completed = true
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name  = try(dependency.project.outputs.project_name, "dp-01")
  instance_name = "${local.project_name}-postgres-main"
}

inputs = {
  project_id = dependency.project.outputs.project_id
  region     = include.base.locals.region
  zone       = include.base.locals.merged.cloud_sql_zones[0]

  name                = local.instance_name
  database_version    = "POSTGRES_17"
  edition             = "ENTERPRISE"
  tier                = "db-f1-micro"
  disk_size           = 10
  disk_type           = "PD_HDD"
  disk_autoresize     = false
  availability_type   = "ZONAL"
  deletion_protection = false

  ipv4_enabled       = false
  private_network    = dependency.network.outputs.network_self_link
  allocated_ip_range = "${local.project_name}-psa-range"
  ssl_mode           = "ENCRYPTED_ONLY"
  server_ca_mode     = "GOOGLE_MANAGED_CAS_CA"

  additional_databases = [
    {
      name      = "postgres"
      charset   = ""
      collation = ""
    },
    {
      name      = "${local.project_name}-app"
      charset   = ""
      collation = ""
    }
  ]

  additional_users = [
    {
      name            = "${local.project_name}-app"
      password        = ""
      random_password = true
      type            = "BUILT_IN"
    }
  ]

  backup_configuration = {
    enabled                        = true
    start_time                     = "02:00"
    location                       = null
    point_in_time_recovery_enabled = false
    transaction_log_retention_days = 1
    retained_backups               = 7
    retention_unit                 = "COUNT"
  }

  maintenance_window_day          = 7
  maintenance_window_hour         = 3
  maintenance_window_update_track = "stable"

  database_flags = []

  user_labels = merge(
    include.base.locals.standard_labels,
    {
      component = "cloud-sql"
      engine    = "postgres"
      instance  = "main"
    }
  )
}
