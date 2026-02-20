# BigQuery dataset example for data platform

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "bigquery_template" {
  path           = "${get_repo_root()}/_common/templates/bigquery.hcl"
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

locals {
  project_name = try(dependency.project.outputs.project_name, "dp-dev-01")
  dataset_id   = replace("${local.project_name}_landing_example", "-", "_")
}

inputs = {
  project_id = dependency.project.outputs.project_id

  dataset_id                  = local.dataset_id
  friendly_name               = "Landing Example Dataset"
  description                 = "Example landing dataset for raw data ingestion in ${local.project_name}"
  location                    = include.base.locals.region
  delete_contents_on_destroy  = true
  default_table_expiration_ms = null

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "bigquery"
      purpose   = "landing-zone"
      dataset   = "landing-example"
    }
  )
}
