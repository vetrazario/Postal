#!/bin/bash
# ===========================================
# Generate postal.yml from template
# Uses environment variables to replace placeholders
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$PROJECT_DIR/config/postal.yml.template"
OUTPUT_FILE="$PROJECT_DIR/config/postal.yml"

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "ERROR: Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Load .env file if exists
if [ -f "$PROJECT_DIR/.env" ]; then
    echo "Loading environment from .env file..."
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Check required environment variables
REQUIRED_VARS=(
    "DOMAIN"
    "MARIADB_PASSWORD"
    "RABBITMQ_PASSWORD"
    "POSTAL_SIGNING_KEY"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "ERROR: Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Please set these variables in .env file or environment"
    exit 1
fi

# Generate postal.yml from template
echo "Generating postal.yml from template..."

# Use envsubst to replace variables
envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"

# Verify the output doesn't contain unsubstituted variables
if grep -q '\${' "$OUTPUT_FILE"; then
    echo "WARNING: Some variables were not substituted:"
    grep '\${' "$OUTPUT_FILE" || true
fi

echo "Generated: $OUTPUT_FILE"

# Set proper permissions (readable by owner only)
chmod 600 "$OUTPUT_FILE"

echo "Done! postal.yml has been generated successfully."

