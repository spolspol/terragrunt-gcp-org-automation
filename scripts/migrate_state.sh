#!/bin/bash

# State migration script for moving to new bucket
# This script migrates all terragrunt modules to the new state bucket

set -euo pipefail

export GOOGLE_APPLICATION_CREDENTIALS="$HOME/tofu-sa-org-key.json"

echo "🔄 Starting state migration to new bucket..."

# List of all terragrunt directories (excluding cache)
# Update this list based on your actual module structure
MODULES=(
    # Example folder and project structure
    "perimeter/folder"
    "perimeter/data-staging/project"
    "perimeter/data-staging/vpc-network"
    "perimeter/data-staging/europe-west2/buckets/static-content"
    "perimeter/data-staging/europe-west2/compute/web-server-01"
    "perimeter/data-staging/europe-west2/compute/web-server-01/vm"
    "perimeter/data-staging/europe-west2/external-ips/web-server-ip"
    "perimeter/data-staging/secrets/ssl-cert-email"

    # Development environment example
    "dev/org-dp-dev-01/project"
    "dev/org-dp-dev-01/vpc-network"
    "dev/org-dp-dev-01/europe-west2/private-service-access"
    "dev/org-dp-dev-01/europe-west2/bigquery/analytics-dataset"
    "dev/org-dp-dev-01/europe-west2/buckets/backup-storage"
    "dev/org-dp-dev-01/europe-west2/buckets/data-processing"
    "dev/org-dp-dev-01/europe-west2/buckets/terraform-state"
    "dev/org-dp-dev-01/europe-west2/cloud-sql/sql-server-main"
    "dev/org-dp-dev-01/europe-west2/compute/web-server-01"
    "dev/org-dp-dev-01/europe-west2/compute/web-server-01/vm"
    "dev/org-dp-dev-01/europe-west2/compute/sql-server-01"
    "dev/org-dp-dev-01/europe-west2/compute/sql-server-01/vm"
    "dev/org-dp-dev-01/europe-west2/external-ips/web-server-ip"
    "dev/org-dp-dev-01/europe-west2/external-ips/sql-server-ip"
    "dev/org-dp-dev-01/europe-west2/firewall-rules/allow-web-traffic"
    "dev/org-dp-dev-01/secrets/ssl-cert-email"
    "dev/org-dp-dev-01/secrets/sql-server-admin-password"
    "dev/org-dp-dev-01/secrets/sql-server-dba-password"
)

FAILED_MODULES=()
SUCCESS_COUNT=0

cd "$(dirname "$0")/live/non-production"

for module in "${MODULES[@]}"; do
    echo "📦 Migrating module: $module"

    if [ -d "$module" ]; then
        cd "$module"

        # Check if this module has existing state that needs migration
        if terragrunt show >/dev/null 2>&1; then
            echo "  ✅ State already in new bucket: $module"
        else
            if terragrunt init -migrate-state -force-copy -no-color >/dev/null 2>&1; then
                echo "  ✅ Successfully migrated: $module"
                ((SUCCESS_COUNT++))
            else
                echo "  ❌ Failed to migrate: $module"
                FAILED_MODULES+=("$module")
            fi
        fi

        cd - >/dev/null
    else
        echo "  ⚠️  Directory not found: $module"
        FAILED_MODULES+=("$module")
    fi
done

echo ""
echo "📊 Migration Summary:"
echo "✅ Successfully migrated: $SUCCESS_COUNT modules"
echo "❌ Failed migrations: ${#FAILED_MODULES[@]} modules"

if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
    echo ""
    echo "Failed modules:"
    for failed in "${FAILED_MODULES[@]}"; do
        echo "  - $failed"
    done
    exit 1
else
    echo ""
    echo "🎉 All modules successfully migrated to new state bucket!"
fi
