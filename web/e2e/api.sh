#!/bin/sh
# Start a throwaway API for the end-to-end tests: fresh database, demo profile only,
# one admin; each test creates its own learner through the admin API.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
dir=${CAPSA_E2E_DIR:-$(mktemp -d)}
export CAPSA_DATABASE_URL="sqlite:///$dir/e2e.sqlite"
export CAPSA_PROFILE_DIR="$repo/profiles/demo"
cd "$repo"
rm -f "$dir"/e2e.sqlite*
uv run -q capsa db upgrade >/dev/null
echo 'e2e-admin-123' | uv run -q capsa user add admin --admin --password-stdin >/dev/null
exec uv run -q uvicorn --factory capsa.app:create_app --host 127.0.0.1 --port "${CAPSA_E2E_API_PORT:-8765}"
