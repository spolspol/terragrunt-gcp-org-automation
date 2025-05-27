#!/bin/bash
# Setup script for Terragrunt secrets environment variables
# This script sets up the environment variables needed for secrets in your infrastructure

set -e

echo "=== Terragrunt Secrets Environment Setup ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to prompt for secret value
prompt_for_secret() {
    local var_name="$1"
    local description="$2"
    local current_value="${!var_name}"

    echo -e "${BLUE}Setting up: ${var_name}${NC}"
    echo -e "${YELLOW}Description: ${description}${NC}"

    if [[ -n "$current_value" ]]; then
        echo -e "${GREEN}Current value is already set (${#current_value} characters)${NC}"
        read -p "Do you want to update it? (y/N): " update_choice
        if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Keeping existing value${NC}"
            echo ""
            return
        fi
    fi

    if [[ "$var_name" == "API_KEY_SECRET" ]] || [[ "$var_name" == "DB_CONNECTION_STRING" ]]; then
        read -s -p "Enter value (hidden): " new_value
        echo ""
    elif [[ "$var_name" == "SERVICE_ACCOUNT_KEY" ]]; then
        echo "Enter the service account key content (paste the entire JSON, press Ctrl+D when done):"
        new_value=$(cat)
    else
        read -p "Enter value: " new_value
    fi

    if [[ -n "$new_value" ]]; then
        export "$var_name"="$new_value"
        echo -e "${GREEN}✓ ${var_name} has been set${NC}"
    else
        echo -e "${RED}✗ No value provided for ${var_name}${NC}"
    fi
    echo ""
}

# Function to validate JSON format
validate_json() {
    local json_content="$1"
    if echo "$json_content" | jq . >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to save environment variables to a file
save_to_file() {
    local env_file="$1"
    echo "# Terragrunt Secrets Environment Variables" > "$env_file"
    echo "# Generated on $(date)" >> "$env_file"
    echo "" >> "$env_file"

    for var in API_SECRET_VALUE API_KEY_SECRET DB_CONNECTION_STRING SERVICE_ACCOUNT_KEY; do
        if [[ -n "${!var}" ]]; then
            if [[ "$var" == "SERVICE_ACCOUNT_KEY" ]]; then
                echo "export $var='${!var}'" >> "$env_file"
            else
                echo "export $var=\"${!var}\"" >> "$env_file"
            fi
        fi
    done

    echo -e "${GREEN}Environment variables saved to: ${env_file}${NC}"
    echo -e "${YELLOW}To load these variables in the future, run: source ${env_file}${NC}"
}

# Main setup process
echo "This script will help you set up the required environment variables for your application secrets."
echo ""

# Setup each secret
prompt_for_secret "API_SECRET_VALUE" "API secret value for your application"
prompt_for_secret "API_KEY_SECRET" "API key for external service integration"
prompt_for_secret "DB_CONNECTION_STRING" "Database connection string"

# Special handling for service account key
echo -e "${BLUE}Setting up: SERVICE_ACCOUNT_KEY${NC}"
echo -e "${YELLOW}Description: Service account key content (JSON format)${NC}"

if [[ -n "$SERVICE_ACCOUNT_KEY" ]]; then
    echo -e "${GREEN}Current service account key is already set (${#SERVICE_ACCOUNT_KEY} characters)${NC}"
    read -p "Do you want to update it? (y/N): " update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Keeping existing service account key${NC}"
        echo ""
    else
        prompt_for_secret "SERVICE_ACCOUNT_KEY" "Service account key content (JSON format)"
    fi
else
    echo "You can either:"
    echo "1. Paste the service account key content directly"
    echo "2. Load from a file"
    echo ""
    read -p "Choose option (1/2): " key_option

    if [[ "$key_option" == "2" ]]; then
        read -p "Enter path to service account key file: " key_file_path
        if [[ -f "$key_file_path" ]]; then
            SERVICE_ACCOUNT_KEY=$(cat "$key_file_path")
            export SERVICE_ACCOUNT_KEY
            echo -e "${GREEN}✓ Service account key loaded from file${NC}"
        else
            echo -e "${RED}✗ File not found: $key_file_path${NC}"
        fi
    else
        prompt_for_secret "SERVICE_ACCOUNT_KEY" "Service account key content (JSON format)"
    fi
fi

# Validate service account key if provided
if [[ -n "$SERVICE_ACCOUNT_KEY" ]]; then
    if validate_json "$SERVICE_ACCOUNT_KEY"; then
        echo -e "${GREEN}✓ Service account key format appears valid${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Service account key format may not be valid JSON${NC}"
        echo -e "${YELLOW}  Make sure it's a valid GCP service account key${NC}"
    fi
fi

echo ""
echo "=== Summary ==="
echo ""

# Display summary
for var in API_SECRET_VALUE API_KEY_SECRET DB_CONNECTION_STRING SERVICE_ACCOUNT_KEY; do
    if [[ -n "${!var}" ]]; then
        if [[ "$var" == "API_KEY_SECRET" ]] || [[ "$var" == "DB_CONNECTION_STRING" ]]; then
            echo -e "${GREEN}✓ $var: [HIDDEN]${NC}"
        elif [[ "$var" == "SERVICE_ACCOUNT_KEY" ]]; then
            echo -e "${GREEN}✓ $var: [${#SERVICE_ACCOUNT_KEY} characters]${NC}"
        else
            echo -e "${GREEN}✓ $var: ${!var}${NC}"
        fi
    else
        echo -e "${RED}✗ $var: Not set${NC}"
    fi
done

echo ""

# Check if all required variables are set
missing_vars=()
for var in API_SECRET_VALUE API_KEY_SECRET DB_CONNECTION_STRING SERVICE_ACCOUNT_KEY; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ All required environment variables are set!${NC}"
    echo ""

    # Offer to save to file
    read -p "Do you want to save these variables to a file? (y/N): " save_choice
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        default_file=".env.secrets"
        read -p "Enter filename (default: $default_file): " env_file
        env_file=${env_file:-$default_file}
        save_to_file "$env_file"
    fi

    echo ""
    echo -e "${GREEN}You can now run Terragrunt commands to deploy your secrets.${NC}"
    echo -e "${YELLOW}Example: terragrunt apply${NC}"
else
    echo -e "${RED}✗ Missing required variables: ${missing_vars[*]}${NC}"
    echo -e "${YELLOW}Please run this script again to set the missing variables.${NC}"
fi

echo ""
echo "=== Next Steps ==="
echo "1. Ensure all environment variables are set"
echo "2. Navigate to your secret directory (e.g., secrets/api-secret/)"
echo "3. Run 'terragrunt plan' to verify the configuration"
echo "4. Run 'terragrunt apply' to create the secrets"
echo ""