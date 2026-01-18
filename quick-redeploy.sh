#!/bin/bash
# Quick redeploy - pull and rebuild API only
set -e

cd "$(dirname "$0")"

echo "Pulling latest changes..."
git pull origin claude/project-analysis-errors-Awt4F

echo "Rebuilding API..."
docker compose stop api
docker compose rm -f api
docker compose build --no-cache api
docker compose up -d

echo "Waiting 10 seconds..."
sleep 10

echo "✅ Redeployed! Run ./test-error-monitor-after-fix.sh to test"
