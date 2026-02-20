#!/bin/bash
# Simple setup script for Terragrunt secrets environment variables
# This is a minimal version for quick setup

echo "=== Quick Secrets Environment Setup ==="
echo ""
echo "Setting up environment variables for application secrets..."
echo ""

# Prompt for each secret
echo "Enter API secret value:"
read -p "API_SECRET_VALUE: " API_SECRET_VALUE
export API_SECRET_VALUE

echo ""
echo "Enter API key:"
read -s -p "API_KEY_SECRET: " API_KEY_SECRET
export API_KEY_SECRET
echo ""

echo ""
echo "Enter database connection string:"
read -s -p "DB_CONNECTION_STRING: " DB_CONNECTION_STRING
export DB_CONNECTION_STRING
echo ""

echo ""
echo "Enter path to service account key file:"
read -p "Service Account Key File Path: " sa_key_path

if [[ -f "$sa_key_path" ]]; then
    export SERVICE_ACCOUNT_KEY=$(cat "$sa_key_path")
    echo "✓ Service account key file loaded"
else
    echo "Error: File not found: $sa_key_path"
    echo "You can set SERVICE_ACCOUNT_KEY manually:"
    echo "export SERVICE_ACCOUNT_KEY=\$(cat /path/to/your/key.json)"
    exit 1
fi

echo ""
echo "✓ All environment variables set!"
echo ""
echo "Variables set:"
echo "  API_SECRET_VALUE: $API_SECRET_VALUE"
echo "  API_KEY_SECRET: [HIDDEN]"
echo "  DB_CONNECTION_STRING: [HIDDEN]"
echo "  SERVICE_ACCOUNT_KEY: [${#SERVICE_ACCOUNT_KEY} characters]"
echo ""
echo "Now you can deploy your secrets with:"
echo "  cd live/non-production/development/dev-01/secrets"
echo "  terragrunt run-all apply"
