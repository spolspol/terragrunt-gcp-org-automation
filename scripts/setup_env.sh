#!/bin/bash
# Setup script for Terragrunt environment variables

# Set the project-specific variables
export TF_VAR_project="dev-02"
export TF_VAR_region="europe-west2"
export TF_VAR_environment_type="non-production"

# GCP Authentication - uncomment one of the following:
# Option 1: Service Account Key
# export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your-service-account-key.json"

# Option 2: Use gcloud auth (if already authenticated)
# gcloud auth application-default login

echo "Environment variables set:"
echo "  TF_VAR_project: $TF_VAR_project"
echo "  TF_VAR_region: $TF_VAR_region"
echo "  TF_VAR_environment_type: $TF_VAR_environment_type"
echo ""
echo "Remember to set up GCP authentication!"
echo "  - Either set GOOGLE_APPLICATION_CREDENTIALS"
echo "  - Or run: gcloud auth application-default login"
