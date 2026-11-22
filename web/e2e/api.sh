#!/bin/sh
# Start a throwaway API for the end-to-end tests: fresh database, demo profile only,
# one learner with the demo profile released.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
dir=${CAPSA_E2E_DIR:-$(mktemp -d)}
export CAPSA_DATABASE_URL="sqlite:///$dir/e2e.sqlite"
export CAPSA_PROFILE_DIR="$repo/profiles/demo"
cd "$repo"
rm -f "$dir"/e2e.sqlite*
uv run -q capsa db upgrade >/dev/null
echo 'e2e-pass-123' | uv run -q capsa user add lena --password-stdin >/dev/null
uv run -q capsa user grant lena demo-latin >/dev/null
exec uv run -q uvicorn --factory capsa.app:create_app --host 127.0.0.1 --port "${CAPSA_E2E_API_PORT:-8765}"
