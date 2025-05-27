#!/bin/bash

# Complete GCP Bootstrap Script
# This script creates the complete initial infrastructure for Terragrunt:
# 1. Service account with organization-level permissions for Terraform operations
# 2. GCP Folder called 'bootstrap' (using the service account)
# 3. GCP Project called 'automation' within the bootstrap folder (using the service account)
# 4. GCS Bucket called 'org-tofu-state' for Terragrunt state storage (using the service account)

set -euo pipefail

# Configuration variables - can be overridden via command line arguments
ORG_ID="${1:-YOUR_ORG_ID}"
BILLING_ACCOUNT="${2:-YOUR_BILLING_ACCOUNT}"
FOLDER_NAME="org-bootstrap"
PROJECT_ID="org-automation"
PROJECT_NAME="automation"
BUCKET_NAME="org-tofu-state"
BILLING_BUCKET_NAME="org-billing-usage-reports"
REGION="europe-west2"
SA_NAME="tofu-sa-org"
SA_DISPLAY_NAME="OpenTofu Service Account for Organization Infrastructure"
SA_DESCRIPTION="Service account for managing GCP infrastructure via Terragrunt/OpenTofu"

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

print_usage() {
    echo "Usage: $0 [ORG_ID] [BILLING_ACCOUNT]"
    echo ""
    echo "Parameters:"
    echo "  ORG_ID          - GCP Organization ID (default: YOUR_ORG_ID)"
    echo "  BILLING_ACCOUNT - Billing Account ID (default: YOUR_BILLING_ACCOUNT)"
    echo ""
    echo "Example:"
    echo "  $0 123456789012 012345-678901-234567"
    echo ""
    echo "This script will create:"
    echo "  • GCP Folder: $FOLDER_NAME"
    echo "  • GCP Project: $PROJECT_ID"
    echo "  • GCS Bucket: $BUCKET_NAME"
    echo "  • Service Account: $SA_NAME with organization-level permissions"
}

# Show usage if help is requested
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
fi

echo "🚀 Starting Complete GCP Bootstrap Process..."
echo ""
log_info "Configuration:"
log_info "  Organization ID: $ORG_ID"
log_info "  Billing Account: $BILLING_ACCOUNT"
log_info "  Folder Name: $FOLDER_NAME"
log_info "  Project ID: $PROJECT_ID"
log_info "  Bucket Name: $BUCKET_NAME"
log_info "  Service Account: $SA_NAME"
echo ""

# Check if gcloud is authenticated
if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q "@"; then
    log_error "No active gcloud authentication found"
    echo "Please run: gcloud auth login"
    exit 1
fi

# Check if required APIs are enabled for the current project
log_info "Checking required GCP APIs..."
REQUIRED_APIS=(
    # Core APIs
    "cloudresourcemanager.googleapis.com"  # Resource Manager API
    "serviceusage.googleapis.com"           # Service Usage API
    "iam.googleapis.com"                    # Identity and Access Management API
    "cloudbilling.googleapis.com"           # Cloud Billing API
    "billingbudgets.googleapis.com"         # Cloud Billing Budget API

    # Compute and Networking
    "compute.googleapis.com"                # Compute Engine API
    "servicenetworking.googleapis.com"     # Service Networking API
    "dns.googleapis.com"                    # Cloud DNS API

    # Storage and Databases
    "storage.googleapis.com"                # Cloud Storage API
    "sqladmin.googleapis.com"               # Cloud SQL Admin API
    "bigquery.googleapis.com"               # BigQuery API

    # Security and Management
    "secretmanager.googleapis.com"         # Secret Manager API
    "cloudkms.googleapis.com"               # Cloud KMS API

    # Monitoring and Logging
    "monitoring.googleapis.com"             # Cloud Monitoring API
    "logging.googleapis.com"                # Cloud Logging API
)

for api in "${REQUIRED_APIS[@]}"; do
    log_info "  Checking $api..."
    if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        log_warning "  $api is not enabled in the current project"
        log_warning "  You may need to enable it manually or run from a project with these APIs enabled"
    fi
done

# Get current project for creating the service account
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$CURRENT_PROJECT" ]]; then
    log_error "No default project set. Please run 'gcloud config set project PROJECT_ID' first."
    exit 1
fi

log_info "Using current project for service account creation: $CURRENT_PROJECT"

echo ""
log_info "=== PHASE 1: Creating Service Account ==="

# Step 1: Create service account in current project
log_info "👤 Creating service account: $SA_NAME"
if gcloud iam service-accounts describe "${SA_NAME}@${CURRENT_PROJECT}.iam.gserviceaccount.com" --project="$CURRENT_PROJECT" >/dev/null 2>&1; then
    log_success "Service account '$SA_NAME' already exists"
else
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name="$SA_DISPLAY_NAME" \
        --description="$SA_DESCRIPTION" \
        --project="$CURRENT_PROJECT"
    log_success "Created service account '$SA_NAME'"
fi

# Get service account email
SA_EMAIL="${SA_NAME}@${CURRENT_PROJECT}.iam.gserviceaccount.com"
log_success "Service account email: $SA_EMAIL"

# Step 2: Generate service account key
log_info "🔑 Generating service account key..."
KEY_FILE="$HOME/${SA_NAME}-key.json"
if [ -f "$KEY_FILE" ]; then
    log_success "Service account key already exists at: $KEY_FILE"
else
    gcloud iam service-accounts keys create "$KEY_FILE" \
        --iam-account="$SA_EMAIL" \
        --project="$CURRENT_PROJECT"
    log_success "Service account key saved to: $KEY_FILE"
fi

echo ""
log_info "=== PHASE 2: Granting Organization Permissions ==="

# Step 3: Organization-level permissions
log_info "🔐 Granting organization-level permissions..."

ORG_ROLES=(
    # Folder management
    "roles/resourcemanager.folderAdmin"

    # Project management
    "roles/resourcemanager.projectCreator"
    "roles/resourcemanager.projectDeleter"
    "roles/resourcemanager.projectIamAdmin"

    # Billing
    "roles/billing.user"

    # Organization-level IAM
    "roles/resourcemanager.organizationAdmin"

    # Security and compliance
    "roles/securitycenter.adminEditor"

    # Essential contacts
    "roles/essentialcontacts.admin"
)

for role in "${ORG_ROLES[@]}"; do
    log_info "  Granting $role at organization level..."
    gcloud organizations add-iam-policy-binding "$ORG_ID" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --quiet 2>/dev/null || log_warning "  Failed to grant $role (may not have permission)"
done

# Step 4: Billing account permissions
log_info "💰 Granting billing account permissions..."

BILLING_ROLES=(
    "roles/billing.admin"
    "roles/billing.projectManager"
)

for role in "${BILLING_ROLES[@]}"; do
    log_info "  Granting $role on billing account..."
    gcloud beta billing accounts add-iam-policy-binding "$BILLING_ACCOUNT" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --quiet 2>/dev/null || log_warning "  Failed to grant $role on billing account"
done

# Step 5: Activate the service account for subsequent operations
log_info "🔄 Activating service account for subsequent operations..."
gcloud auth activate-service-account "$SA_EMAIL" --key-file="$KEY_FILE"
log_success "Service account activated"

echo ""
log_info "=== PHASE 3: Creating GCP Infrastructure (using service account) ==="

# Step 6: Create GCP Folder
log_info "📁 Creating GCP Folder: $FOLDER_NAME"

# For bootstrap folder, use known ID if we can't create/list
if [ "$FOLDER_NAME" = "org-bootstrap" ]; then
    # Use known bootstrap folder ID
    EXISTING_BOOTSTRAP_ID="YOUR_BOOTSTRAP_FOLDER_ID"
    FOLDER_ID="folders/$EXISTING_BOOTSTRAP_ID"
    log_info "Using known bootstrap folder ID: $FOLDER_ID"
    log_success "Folder '$FOLDER_NAME' exists with ID: $FOLDER_ID"
else
    # Try to check if folder already exists first
    FOLDER_ID=$(gcloud resource-manager folders list \
        --filter="displayName:$FOLDER_NAME AND parent.id:$ORG_ID" \
        --format="value(name)" 2>/dev/null || true)

    if [ -n "$FOLDER_ID" ]; then
        log_success "Folder '$FOLDER_NAME' already exists with ID: $FOLDER_ID"
    else
        # Try to create folder (it might already exist or creation might succeed)
        FOLDER_ID=$(gcloud resource-manager folders create \
            --display-name="$FOLDER_NAME" \
            --organization="$ORG_ID" \
            --format="value(name)" 2>/dev/null || true)

        if [ -n "$FOLDER_ID" ]; then
            log_success "Created folder '$FOLDER_NAME' with ID: $FOLDER_ID"
        else
            log_error "Failed to create or find folder '$FOLDER_NAME'"
            log_error "Please ensure you have resourcemanager.folders.create permission"
            exit 1
        fi
    fi
fi

# Extract numeric folder ID from the full resource name
FOLDER_NUMERIC_ID=$(echo "$FOLDER_ID" | sed 's/folders\///')

# Step 7: Create GCP Project
log_info "🏗️  Creating GCP Project: $PROJECT_ID"
# Check if project already exists first
if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    log_success "Project '$PROJECT_ID' already exists"
else
    if gcloud projects create "$PROJECT_ID" \
        --name="$PROJECT_NAME" \
        --folder="$FOLDER_NUMERIC_ID" 2>/dev/null; then
        log_success "Created project '$PROJECT_ID'"
    else
        log_error "Failed to create project '$PROJECT_ID'"
        exit 1
    fi
fi

# Step 8: Link billing account to project
log_info "💳 Linking billing account to project..."
# Check if billing account is already linked
CURRENT_BILLING=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || true)
if [[ "$CURRENT_BILLING" == *"$BILLING_ACCOUNT"* ]]; then
    log_success "Billing account already linked to project"
else
    if gcloud billing projects link "$PROJECT_ID" \
        --billing-account="$BILLING_ACCOUNT" 2>/dev/null; then
        log_success "Linked billing account to project"
    else
        log_warning "Failed to link billing account. You may need to do this manually."
    fi
fi

# Step 9: Enable required APIs in the new project
log_info "🔧 Enabling required APIs in project..."
gcloud config set project "$PROJECT_ID"

ENABLED_COUNT=0
FAILED_COUNT=0
ALREADY_ENABLED_COUNT=0

for api in "${REQUIRED_APIS[@]}"; do
    log_info "  Checking $api..."

    # Check if API is already enabled
    if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        log_success "    Already enabled: $api"
        ((ALREADY_ENABLED_COUNT++))
    else
        # Enable the API
        log_info "    Enabling: $api..."
        if gcloud services enable "$api" >/dev/null 2>&1; then
            log_success "    Enabled: $api"
            ((ENABLED_COUNT++))
        else
            log_warning "    Failed to enable: $api"
            ((FAILED_COUNT++))
        fi
    fi
done

log_info "API Summary: $ENABLED_COUNT enabled, $ALREADY_ENABLED_COUNT already enabled, $FAILED_COUNT failed"

# Step 10: Create GCS bucket for Terragrunt state
log_info "🪣 Creating GCS bucket: $BUCKET_NAME"
# Check if bucket already exists first
if gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
    log_success "Bucket 'gs://$BUCKET_NAME' already exists"
else
    if gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://$BUCKET_NAME" 2>/dev/null; then
        log_success "Created bucket 'gs://$BUCKET_NAME'"
    else
        log_error "Failed to create bucket 'gs://$BUCKET_NAME'"
        exit 1
    fi
fi

# Step 11: Enable versioning on the bucket
log_info "🔄 Enabling versioning on state bucket..."
if gsutil versioning set on "gs://$BUCKET_NAME"; then
    log_success "Enabled versioning on bucket"
else
    log_warning "Failed to enable versioning"
fi

# Step 12: Set uniform bucket-level access
log_info "🔒 Setting uniform bucket-level access..."
if gsutil uniformbucketlevelaccess set on "gs://$BUCKET_NAME"; then
    log_success "Enabled uniform bucket-level access"
else
    log_warning "Failed to set uniform bucket-level access"
fi

# Step 13: Create billing usage reports bucket
log_info "📊 Creating billing usage reports bucket: $BILLING_BUCKET_NAME"
# Check if billing bucket already exists first
if gsutil ls "gs://$BILLING_BUCKET_NAME" >/dev/null 2>&1; then
    log_success "Billing bucket 'gs://$BILLING_BUCKET_NAME' already exists"
else
    if gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://$BILLING_BUCKET_NAME" 2>/dev/null; then
        log_success "Created billing bucket 'gs://$BILLING_BUCKET_NAME'"
    else
        log_error "Failed to create billing bucket 'gs://$BILLING_BUCKET_NAME'"
        # Don't exit on billing bucket failure as it's not critical for basic operations
        log_warning "Continuing without billing bucket - you can create it manually later"
    fi
fi

# Step 14: Configure billing bucket (if it exists)
if gsutil ls "gs://$BILLING_BUCKET_NAME" >/dev/null 2>&1; then
    log_info "🔄 Configuring billing bucket settings..."

    # Enable versioning on billing bucket
    if gsutil versioning set on "gs://$BILLING_BUCKET_NAME" >/dev/null 2>&1; then
        log_success "Enabled versioning on billing bucket"
    else
        log_warning "Failed to enable versioning on billing bucket"
    fi

    # Set uniform bucket-level access on billing bucket
    if gsutil uniformbucketlevelaccess set on "gs://$BILLING_BUCKET_NAME" >/dev/null 2>&1; then
        log_success "Enabled uniform bucket-level access on billing bucket"
    else
        log_warning "Failed to set uniform bucket-level access on billing bucket"
    fi
fi

echo ""
log_info "=== PHASE 2: Creating Service Account ==="

# Step 8: Create service account in bootstrap project
log_info "👤 Creating service account in bootstrap project: $SA_NAME"
if gcloud iam service-accounts describe "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log_success "Service account '$SA_NAME' already exists in bootstrap project"
else
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name="$SA_DISPLAY_NAME" \
        --description="$SA_DESCRIPTION" \
        --project="$PROJECT_ID"
    log_success "Created service account '$SA_NAME' in bootstrap project"
fi

# Get service account email
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
log_success "Service account email: $SA_EMAIL"

echo ""
log_info "=== PHASE 3: Granting Permissions ==="

# Step 9: Organization-level permissions
log_info "🔐 Granting organization-level permissions..."

ORG_ROLES=(
    # Folder management
    "roles/resourcemanager.folderAdmin"

    # Project management
    "roles/resourcemanager.projectCreator"
    "roles/resourcemanager.projectDeleter"
    "roles/resourcemanager.projectIamAdmin"

    # Billing
    "roles/billing.user"

    # Organization-level IAM
    "roles/resourcemanager.organizationAdmin"

    # Security and compliance
    "roles/securitycenter.adminEditor"

    # Essential contacts
    "roles/essentialcontacts.admin"
)

# Note: Organization and billing permissions were already granted in Phase 2

# Step 13: Project-level permissions for the bootstrap project
log_info "🏗️  Granting project-level permissions to bootstrap project..."

PROJECT_ROLES=(
    # Core project management
    "roles/editor"
    "roles/iam.securityAdmin"
    "roles/resourcemanager.projectIamAdmin"

    # Compute Engine
    "roles/compute.admin"
    "roles/compute.networkAdmin"
    "roles/compute.securityAdmin"

    # VPC and Networking
    "roles/servicenetworking.networksAdmin"
    "roles/dns.admin"

    # Cloud SQL
    "roles/cloudsql.admin"

    # Cloud Storage
    "roles/storage.admin"

    # BigQuery
    "roles/bigquery.admin"

    # Secret Manager
    "roles/secretmanager.admin"

    # Monitoring and Logging
    "roles/monitoring.admin"
    "roles/logging.admin"

    # Service Account management
    "roles/iam.serviceAccountAdmin"
    "roles/iam.serviceAccountKeyAdmin"
    "roles/iam.serviceAccountTokenCreator"

    # API management
    "roles/serviceusage.serviceUsageAdmin"

    # Additional security roles
    "roles/cloudkms.admin"
    "roles/orgpolicy.policyAdmin"
)

for role in "${PROJECT_ROLES[@]}"; do
    log_info "  Granting $role on project $PROJECT_ID..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --quiet 2>/dev/null || log_warning "  Failed to grant $role on project"
done

# Step 14: Restore original user authentication
log_info "🔄 Restoring original user authentication..."
gcloud config set project "$CURRENT_PROJECT"
# Reactivate user account (will prompt if needed)
if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -v "$SA_EMAIL" | grep -q "@"; then
    log_warning "Original user authentication may need to be restored manually"
    log_info "Run: gcloud auth login"
else
    log_success "Original user authentication restored"
fi

echo ""
log_info "=== PHASE 5: Creating Helper Scripts ==="

# Step 15: Create helper script for applying project permissions
cat > scripts/apply-project-permissions.sh << EOF
#!/bin/bash

# Helper script to apply project-level permissions to new projects
# Usage: ./apply-project-permissions.sh PROJECT_ID

PROJECT_ID="\${1:-}"
SA_EMAIL="$SA_EMAIL"

if [[ -z "\$PROJECT_ID" ]]; then
    echo "Usage: \$0 PROJECT_ID"
    echo "Example: \$0 my-new-project"
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

echo "Applying core permissions to project: \$PROJECT_ID"
for role in "\${CORE_ROLES[@]}"; do
    echo "Granting \$role..."
    gcloud projects add-iam-policy-binding "\$PROJECT_ID" \\
        --member="serviceAccount:\$SA_EMAIL" \\
        --role="\$role" \\
        --quiet
done

echo "Core permissions applied successfully!"
EOF

chmod +x scripts/apply-project-permissions.sh
log_success "Created helper script: scripts/apply-project-permissions.sh"

echo ""
log_success "🎉 Complete Bootstrap Process Finished Successfully!"
echo ""
echo "📋 Summary:"
echo "════════════════════════════════════════════════════════════════"
log_info "Infrastructure Created:"
echo "  • Folder: $FOLDER_NAME (ID: $FOLDER_NUMERIC_ID)"
echo "  • Project: $PROJECT_ID"
echo "  • Bucket: gs://$BUCKET_NAME"
echo "  • Service Account: $SA_EMAIL"
echo "  • Key File: $KEY_FILE"
echo "  • Helper Script: scripts/apply-project-permissions.sh"
echo ""
log_info "Next Steps:"
echo "════════════════════════════════════════════════════════════════"
echo "1. 🔧 Update root.hcl to use the new state bucket:"
echo "     bucket = \"$BUCKET_NAME\""
echo "     project = \"$PROJECT_ID\""
echo ""
echo "2. 🔐 Set up authentication environment:"
echo "     export GOOGLE_APPLICATION_CREDENTIALS=\"$KEY_FILE\""
echo "     export GOOGLE_PROJECT=\"$PROJECT_ID\""
echo ""
echo "3. 🧪 Test Terragrunt with the new setup:"
echo "     source scripts/setup_env.sh"
echo "     terragrunt init"
echo ""
echo "4. 🏗️  For new projects, run:"
echo "     ./scripts/apply-project-permissions.sh NEW_PROJECT_ID"
echo ""
log_warning "SECURITY RECOMMENDATIONS:"
echo "════════════════════════════════════════════════════════════════"
echo "• Store the key file securely (consider Google Secret Manager)"
echo "• Set up key rotation schedule"
echo "• Monitor service account usage via Cloud Audit Logs"
echo "• Apply principle of least privilege for project-specific permissions"
echo ""
log_success "Your GCP infrastructure is now ready for Terragrunt deployments!"
