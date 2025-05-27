#!/bin/bash
#
# Save Terraform/OpenTofu plan output as structured JSON artifact
# Usage: ./save-plan-artifact.sh <plan-output-file> <artifact-name>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_OUTPUT_FILE="${1:-}"
ARTIFACT_NAME="${2:-plan-summary}"

if [[ -z "$PLAN_OUTPUT_FILE" ]]; then
    echo "❌ Error: Plan output file is required"
    echo "Usage: $0 <plan-output-file> [artifact-name]"
    exit 1
fi

if [[ ! -f "$PLAN_OUTPUT_FILE" ]]; then
    echo "❌ Error: Plan output file '$PLAN_OUTPUT_FILE' not found"
    exit 1
fi

echo "🔍 Processing plan output: $PLAN_OUTPUT_FILE"

# Parse the plan output to JSON
PARSED_JSON=$(python3 "$SCRIPT_DIR/parse-plan-output.py" "$PLAN_OUTPUT_FILE")

# Create artifacts directory if it doesn't exist
mkdir -p artifacts

# Save parsed plan as JSON artifact
ARTIFACT_FILE="artifacts/${ARTIFACT_NAME}.json"
echo "$PARSED_JSON" > "$ARTIFACT_FILE"

echo "✅ Plan artifact saved: $ARTIFACT_FILE"

# If running in GitHub Actions, set outputs
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "plan-artifact-path=$ARTIFACT_FILE" >> "$GITHUB_OUTPUT"

    # Extract summary for easy access
    RESOURCES_TO_CREATE=$(echo "$PARSED_JSON" | jq -r '.summary.to_create')
    RESOURCES_TO_UPDATE=$(echo "$PARSED_JSON" | jq -r '.summary.to_update')
    RESOURCES_TO_DESTROY=$(echo "$PARSED_JSON" | jq -r '.summary.to_destroy')
    RESOURCES_TO_REPLACE=$(echo "$PARSED_JSON" | jq -r '.summary.to_replace')

    echo "resources-to-create=$RESOURCES_TO_CREATE" >> "$GITHUB_OUTPUT"
    echo "resources-to-update=$RESOURCES_TO_UPDATE" >> "$GITHUB_OUTPUT"
    echo "resources-to-destroy=$RESOURCES_TO_DESTROY" >> "$GITHUB_OUTPUT"
    echo "resources-to-replace=$RESOURCES_TO_REPLACE" >> "$GITHUB_OUTPUT"

    echo "📊 Plan Summary:"
    echo "  • To Create: $RESOURCES_TO_CREATE"
    echo "  • To Update: $RESOURCES_TO_UPDATE"
    echo "  • To Destroy: $RESOURCES_TO_DESTROY"
    echo "  • To Replace: $RESOURCES_TO_REPLACE"
fi

# Clean up raw plan file if requested
if [[ "${CLEANUP_RAW:-false}" == "true" ]]; then
    echo "🧹 Cleaning up raw plan file: $PLAN_OUTPUT_FILE"
    rm -f "$PLAN_OUTPUT_FILE"
fi

echo "✅ Plan processing complete"
