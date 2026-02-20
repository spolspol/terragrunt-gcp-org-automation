#!/bin/bash
#
# Bootstrap script for Nginx web server
# This script downloads and executes the main setup script from GCS
#

set -euo pipefail

# Template variables (replaced by Terragrunt)
PROJECT_ID="${project_id}"
BUCKET_NAME="${bucket_name}"
INSTANCE_NAME="${instance_name}"
REGION="${region}"
STATIC_CONTENT_BUCKET="${static_content_bucket}"
SSL_CERT_EMAIL_SECRET="${ssl_cert_email_secret}"
SSL_DOMAINS_SECRET="${ssl_domains_secret}"

# Logging setup
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting nginx web server bootstrap process..."

# Export environment variables for the setup script
export PROJECT_ID
export BUCKET_NAME
export INSTANCE_NAME
export REGION
export STATIC_CONTENT_BUCKET
export SSL_CERT_EMAIL_SECRET
export SSL_DOMAINS_SECRET

# Download the main setup script from GCS
SETUP_SCRIPT="/tmp/nginx-setup.sh"
log "Downloading setup script from gs://$BUCKET_NAME/$INSTANCE_NAME/nginx-setup.sh"

if gsutil cp "gs://$BUCKET_NAME/$INSTANCE_NAME/nginx-setup.sh" "$SETUP_SCRIPT"; then
    log "Successfully downloaded setup script"
else
    log "ERROR: Failed to download setup script"
    exit 1
fi

# Make the script executable
chmod +x "$SETUP_SCRIPT"

# Execute the setup script
log "Executing nginx setup script..."
if "$SETUP_SCRIPT"; then
    log "Nginx setup completed successfully"
else
    log "ERROR: Nginx setup failed"
    exit 1
fi

log "Bootstrap process completed"
