#!/bin/bash
#
# Setup pre-commit hooks for the repository
# This script installs pre-commit and configures the hooks
#

set -euo pipefail

echo "🔧 Setting up pre-commit hooks..."

# Check if pre-commit is installed
if ! command -v pre-commit >/dev/null 2>&1; then
    echo "📦 Installing pre-commit..."

    # Try different installation methods
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install pre-commit
    elif command -v pip >/dev/null 2>&1; then
        pip install pre-commit
    elif command -v brew >/dev/null 2>&1; then
        brew install pre-commit
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y pre-commit
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y pre-commit
    else
        echo "❌ Could not install pre-commit automatically"
        echo "Please install pre-commit manually:"
        echo "  pip install pre-commit"
        echo "  # or"
        echo "  brew install pre-commit"
        exit 1
    fi

    echo "✅ pre-commit installed successfully"
else
    echo "✅ pre-commit is already installed"
fi

# Install the git hook scripts
echo "🔗 Installing pre-commit hooks..."
pre-commit install

# Install commit-msg hook for additional validation
pre-commit install --hook-type commit-msg

# Create secrets baseline if it doesn't exist
if [ ! -f .secrets.baseline ]; then
    echo "🔐 Creating secrets baseline..."
    if command -v detect-secrets >/dev/null 2>&1; then
        detect-secrets scan --baseline .secrets.baseline
    else
        echo "⚠️  detect-secrets not installed, creating empty baseline"
        echo '{}' > .secrets.baseline
    fi
fi

# Run pre-commit on all files to check setup
echo "🧪 Testing pre-commit setup..."
if pre-commit run --all-files; then
    echo "✅ Pre-commit setup completed successfully!"
else
    echo "⚠️  Some hooks failed, but setup is complete"
    echo "You may need to fix issues and commit again"
fi

echo ""
echo "📋 Pre-commit hooks configured:"
echo "  • terragrunt hcl format - Formats HCL files"
echo "  • terragrunt hcl format check - Validates HCL formatting"
echo "  • trailing-whitespace - Removes trailing whitespace"
echo "  • end-of-file-fixer - Ensures files end with newline"
echo "  • check-yaml - Validates YAML syntax"
echo "  • check-added-large-files - Prevents large file commits"
echo "  • detect-secrets - Scans for secrets"
echo ""
echo "🎉 Ready to commit with automated quality checks!"
