#!/bin/bash

# Helper script to apply project-level permissions to new projects
# Usage: ./apply-project-permissions.sh PROJECT_ID

PROJECT_ID="${1:-}"
SA_EMAIL="tofu-sa-org@org-automation.iam.gserviceaccount.com"

if [[ -z "$PROJECT_ID" ]]; then
    echo "Usage: $0 PROJECT_ID"
    echo "Example: $0 my-new-project"
    exit 1
fi

# Core permissions needed for most Terraform operations
CORE_ROLES=(
    "roles/editor"
    "roles/iam.securityAdmin"
    "roles/compute.admin"
    "roles/storage.admin"
    "roles/secretmanager.admin"
    "roles/serviceusage.serviceUsageAdmin"
    "roles/cloudsql.admin"
    "roles/bigquery.admin"
)

echo "Applying core permissions to project: $PROJECT_ID"
for role in "${CORE_ROLES[@]}"; do
    echo "Granting $role..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --quiet
done

echo "Core permissions applied successfully!"
