#!/bin/bash
# ===========================================
# Generate postal.yml from template
# ===========================================

set -e

TEMPLATE_FILE="config/postal.yml.example"
OUTPUT_FILE="config/postal.yml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE not found"
    exit 1
fi

# Load environment variables from .env if exists
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Generate postal.yml using envsubst
envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Generated $OUTPUT_FILE from template"

