#!/bin/bash

# Script to add GitHub state bucket to existing infrastructure
# This can be used to add the bucket without running the full bootstrap

set -euo pipefail

# Configuration
PROJECT_ID="org-automation"
GITHUB_STATE_BUCKET_NAME="org-github-tofu-state"
REGION="europe-west2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "Adding GitHub State Bucket to Existing Infrastructure"
echo ""

# Check if gcloud is authenticated
if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q "@"; then
    log_error "No active gcloud authentication found"
    echo "Please run: gcloud auth login"
    exit 1
fi

# Set the project
log_info "Setting project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# Create GitHub state bucket
log_info "Creating GitHub state bucket: $GITHUB_STATE_BUCKET_NAME"
if gsutil ls "gs://$GITHUB_STATE_BUCKET_NAME" >/dev/null 2>&1; then
    log_success "GitHub state bucket 'gs://$GITHUB_STATE_BUCKET_NAME' already exists"
else
    if gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://$GITHUB_STATE_BUCKET_NAME"; then
        log_success "Created GitHub state bucket 'gs://$GITHUB_STATE_BUCKET_NAME'"
    else
        log_error "Failed to create GitHub state bucket 'gs://$GITHUB_STATE_BUCKET_NAME'"
        exit 1
    fi
fi

# Enable versioning on the GitHub state bucket
log_info "Enabling versioning on GitHub state bucket..."
if gsutil versioning set on "gs://$GITHUB_STATE_BUCKET_NAME"; then
    log_success "Enabled versioning on GitHub state bucket"
else
    log_warning "Failed to enable versioning on GitHub state bucket"
fi

# Set uniform bucket-level access on GitHub state bucket
log_info "Setting uniform bucket-level access on GitHub state bucket..."
if gsutil uniformbucketlevelaccess set on "gs://$GITHUB_STATE_BUCKET_NAME"; then
    log_success "Enabled uniform bucket-level access on GitHub state bucket"
else
    log_warning "Failed to set uniform bucket-level access on GitHub state bucket"
fi

echo ""
log_success "GitHub State Bucket Successfully Added!"
echo ""
echo "Summary:"
echo "================================================================"
echo "  Bucket Created: gs://$GITHUB_STATE_BUCKET_NAME"
echo "  Project: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Versioning: Enabled"
echo "  Uniform Access: Enabled"
echo ""
echo "This bucket can now be used for GitHub Actions workflows to store Terraform/OpenTofu state."
