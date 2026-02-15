locals {
  region = "europe-west2"
  zone   = "europe-west2-a"

  cloud_sql_zones = ["europe-west2-a", "europe-west2-b"]

  region_settings = {
    multi_region  = false
    primary_zone  = "europe-west2-a"
    recovery_zone = "europe-west2-b"
  }
}
