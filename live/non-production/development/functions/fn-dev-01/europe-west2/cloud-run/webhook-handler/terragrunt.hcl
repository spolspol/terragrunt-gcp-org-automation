# Webhook handler Cloud Run service

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "base" {
  path   = "${get_repo_root()}/_common/base.hcl"
  expose = true
}

include "cloud_run_template" {
  path           = "${get_repo_root()}/_common/templates/cloud-run.hcl"
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
    network_name      = "mock-network"
    network_self_link = "projects/mock-project/global/networks/mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

dependency "runner_sa" {
  config_path = "../../../iam-service-accounts/cr-runner"
  mock_outputs = {
    email = "cr-runner@mock-project-id.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  skip_outputs                            = false
}

locals {
  project_name = try(dependency.project.outputs.project_name, "fn-dev-01")
  service_name = basename(get_terragrunt_dir())
}

inputs = {
  project_id = dependency.project.outputs.project_id
  location   = include.base.locals.region

  service_name    = "${local.project_name}-${local.service_name}"
  service_account = dependency.runner_sa.outputs.email

  image = "${include.base.locals.region}-docker.pkg.dev/${dependency.project.outputs.project_id}/container-images/webhook-handler:latest"

  limits = {
    cpu    = "1000m"
    memory = "512Mi"
  }

  min_instance_count = 0
  max_instance_count = 5

  vpc_access = {
    network_interfaces = [{
      network    = dependency.network.outputs.network_name
      subnetwork = "${dependency.network.outputs.network_name}-serverless"
    }]
    egress = "PRIVATE_RANGES_ONLY"
  }

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  env_vars = {
    PROJECT_ID = dependency.project.outputs.project_id
    REGION     = include.base.locals.region
  }

  labels = merge(
    include.base.locals.standard_labels,
    {
      component = "cloud-run"
      service   = local.service_name
    }
  )
}
