locals {
  # Region name and settings
  region = "europe-west2"
  zone   = "europe-west2-a"

  # Region-specific service locations
  cloud_sql_zones = ["europe-west2-a", "europe-west2-b"]

  # Standard region settings
  region_settings = {
    multi_region  = false
    primary_zone  = "europe-west2-a"
    recovery_zone = "europe-west2-b"
  }
}
