locals {
  # Common path variables
  repo_root      = get_repo_root()
  common_root    = "${local.repo_root}/_common"
  templates_root = "${local.common_root}/templates"

  # Comprehensive module versions - centralized for consistency
  module_versions = {
    # Google Cloud modules
    bigquery        = "v10.1.0"
    sql_db          = "v15.0.0"
    vm              = "v13.2.4"
    network         = "v11.1.1"
    cloud_router    = "v7.1.0"
    gke             = "v37.0.0"
    cloud_nat       = "v5.3.0"
    iam             = "v8.1.0"
    secret_manager  = "v0.8.0"
    cloud_storage   = "v11.0.0"
    cloud_run       = "v4.0.0"
    cloud_function  = "v3.1.0"
    pubsub          = "v5.0.0"
    load_balancer   = "v8.0.0"
    monitoring      = "v7.1.0"
    project_factory = "v18.0.0"
    folders         = "v5.0.0"
    address         = "v3.2.0"

    # Supporting modules
    terraform_validator = "v0.6.0"
    policy_library      = "v1.2.0"

    # External/common modules
    external_ip_firewall   = "v1.1.0"
    cloudflare             = "v4.0.0"
    null_label             = "v0.25.0"
    private_service_access = "main" # Coalfire module - using main branch

    # Custom modules
    argocd = "main" # Bootstrap ArgoCD module
  }

  # Compute-specific defaults
  compute_defaults = {
    machine_types = {
      production = {
        small  = "e2-small"
        medium = "e2-medium"
        large  = "e2-standatd-2"
      }
      non-production = {
        small  = "e2-micro"
        medium = "e2-small"
        large  = "e2-medium"
      }
    }

    disk_types = {
      production     = "pd-ssd"
      non-production = "pd-standard"
    }

    disk_sizes = {
      os = {
        production     = 50
        non-production = 10
      }
      data = {
        production     = 100
        non-production = 30
      }
    }
  }

  # Common tags applied to all resources
  common_tags = {
    terraform_managed = "true"
    repository        = "terragrunt-gcp-org-automation"
    owner             = "infrastructure-team"
  }

  # Default timeouts for operations
  timeouts = {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  # Default maintenance windows by environment
  maintenance_window = {
    production     = "SUN:02:00-SUN:06:00"
    non-production = "SAT:00:00-SAT:04:00"
  }

  # Common network CIDR ranges by environment
  network_cidrs = {
    production = {
      primary   = "10.0.0.0/20"
      secondary = "10.1.0.0/20"
    }
    non-production = {
      primary   = "10.128.0.0/20"
      secondary = "10.129.0.0/20"
    }
    perimeter = {
      primary   = "10.10.0.0/20"
      secondary = "10.11.0.0/20"
    }
    hub = {
      primary   = "10.0.0.0/16"
      secondary = "10.0.0.0/16"
    }
  }

  # Common module configurations
  module_defaults = {
    enabled_apis = [
      "secretmanager.googleapis.com",
      "compute.googleapis.com",
      "sql-component.googleapis.com",
      "sqladmin.googleapis.com",
      "bigquery.googleapis.com",
      "storage.googleapis.com",
      "iam.googleapis.com",
      "monitoring.googleapis.com",
      "logging.googleapis.com",
      "osconfig.googleapis.com",
      "container.googleapis.com",
      "gkebackup.googleapis.com",
      "gkehub.googleapis.com",
      "artifactregistry.googleapis.com",
      "cloudresourcemanager.googleapis.com"
    ]

    log_retention_days = {
      production     = 365
      non-production = 30
    }

    default_region_mapping = {
      primary   = "europe-west2"
      secondary = "europe-west1"
      backup    = "europe-west3"
    }
  }

  # Default SQL Server configs (for use in terragrunt modules)
  sqlserver_settings = {
    production = {
      database_version      = "SQLSERVER_2022_WEB"
      tier                  = "db-custom-4-15360"
      availability_type     = "ZONAL"
      disk_size             = 32
      disk_type             = "PD_SSD"
      disk_autoresize       = true
      disk_autoresize_limit = 512
      backup_configuration = {
        enabled                        = true
        binary_log_enabled             = null
        start_time                     = "00:00"
        point_in_time_recovery_enabled = true
        retained_backups               = 7
        retention_unit                 = "COUNT"
        transaction_log_retention_days = "7"
      }
      maintenance_window_day          = 7 # Sunday
      maintenance_window_hour         = 2 # 2 AM
      maintenance_window_update_track = "stable"
      deletion_protection_enabled     = false
    }
    non-production = {
      database_version                = "SQLSERVER_2022_WEB"
      tier                            = "db-custom-1-3840"
      disk_size                       = 16
      disk_type                       = "PD_SSD"
      disk_autoresize                 = true
      disk_autoresize_limit           = 64
      maintenance_window_day          = 6 # Saturday
      maintenance_window_hour         = 2 # 2 AM
      maintenance_window_update_track = "stable"
      deletion_protection_enabled     = false
    }
  }

  # Default Compute Instance configs (for use in terragrunt modules)
  compute_instance_settings = {
    production = {
      machine_type        = "e2-standard-2"
      disk_size_gb        = 50
      disk_type           = "pd-ssd"
      preemptible         = false
      automatic_restart   = true
      deletion_protection = true
      min_cpu_platform    = "Intel Cascade Lake"
      network_tier        = "PREMIUM"
      enable_display      = false

      # Boot disk configuration
      boot_disk = {
        auto_delete = true
        image       = "debian-cloud/debian-12"
      }

      # Default scopes for production
      scopes = [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring.write",
        "https://www.googleapis.com/auth/service.management.readonly",
        "https://www.googleapis.com/auth/servicecontrol"
      ]

      # Default tags
      tags = ["terragrunt-managed", "production"]
    }
    non-production = {
      machine_type        = "e2-medium"
      disk_size_gb        = 10
      disk_type           = "pd-ssd"
      preemptible         = false
      automatic_restart   = false
      deletion_protection = false
      min_cpu_platform    = null
      network_tier        = "STANDARD"
      enable_display      = false

      # Boot disk configuration
      boot_disk = {
        auto_delete = true
        image       = "debian-cloud/debian-12"
      }

      # Default scopes for non-production
      scopes = [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring.write"
      ]

      # Default tags
      tags = ["terragrunt-managed", "non-production"]
    }
  }

  # SQL Server Compute Instance specific configs
  compute_sqlserver_settings = {
    production = {
      machine_type        = "n4d-standard-16"
      disk_size_gb        = 200
      disk_type           = "pd-ssd"
      preemptible         = false
      automatic_restart   = true
      deletion_protection = false
      min_cpu_platform    = "Intel Cascade Lake"
      network_tier        = "PREMIUM"
      enable_display      = true

      # Boot disk configuration for SQL Server
      boot_disk = {
        auto_delete = true
        image       = "sql-std-2022-win-2025/sql-2022-standard-windows-2025-dc-v20250515"
      }

      # SQL Server specific scopes
      scopes = [
        "https://www.googleapis.com/auth/devstorage.read_write",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring.write",
        "https://www.googleapis.com/auth/service.management.readonly",
        "https://www.googleapis.com/auth/servicecontrol",
        "https://www.googleapis.com/auth/sqlservice.admin"
      ]

      # SQL Server specific tags
      tags = ["terragrunt-managed", "production", "sql-server", "database"]

      # Additional disks for SQL Server data and logs
      additional_disks = [
        {
          disk_name             = "data-disk"
          device_name           = "data-disk"
          disk_size_gb          = 256
          disk_autoresize       = true
          disk_autoresize_limit = 1024
          disk_type             = "pd-ssd"
          auto_delete           = false
          labels = {
            type = "sqlserver-data"
          }
        },
        {
          disk_name             = "log-disk"
          device_name           = "log-disk"
          disk_size_gb          = 128
          disk_autoresize       = true
          disk_autoresize_limit = 512
          disk_type             = "pd-ssd"
          auto_delete           = false
          labels = {
            type = "sqlserver-logs"
          }
        }
      ]
    }
    non-production = {
      machine_type        = "n2d-highmem-4"
      disk_size_gb        = 50
      disk_type           = "pd-standard"
      auto_delete         = false
      preemptible         = false
      automatic_restart   = true
      deletion_protection = false
      min_cpu_platform    = null
      network_tier        = "STANDARD"
      enable_display      = true

      # Boot disk configuration for SQL Server
      boot_disk = {
        auto_delete = true
        image       = "sql-std-2022-win-2025/sql-2022-web-windows-2025-dc-v20250515"
      }

      # SQL Server specific scopes
      scopes = [
        "https://www.googleapis.com/auth/devstorage.read_write",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring.write",
        "https://www.googleapis.com/auth/sqlservice.admin"
      ]

      # SQL Server specific tags
      tags = ["terragrunt-managed", "non-production", "sql-server", "database"]

      # Additional disks for SQL Server data and logs
      additional_disks = [
        {
          disk_name             = "data-disk"
          device_name           = "data-disk"
          disk_size_gb          = 3027
          disk_type             = "pd-standard"
          disk_autoresize       = true
          disk_autoresize_limit = 3584
          auto_delete           = false
          labels = {
            type = "sqlserver-data"
          }
        },
        {
          disk_name             = "log-disk"
          device_name           = "log-disk"
          disk_size_gb          = 256
          disk_autoresize       = true
          disk_autoresize_limit = 512
          disk_type             = "pd-standard"
          auto_delete           = false
          labels = {
            type = "sqlserver-logs"
          }
        }
      ]
    }
  }
}
