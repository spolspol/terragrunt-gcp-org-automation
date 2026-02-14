locals {
  region       = "europe-west2"
  region_short = "ew2"
  region_name  = "London"

  # Regional labels
  region_labels = {
    region      = local.region
    region_code = local.region_short
    location    = local.region_name
  }
}
