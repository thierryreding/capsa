#!/bin/sh
# Run every check; stops at the first failure. Use before each commit.
set -eu
cd "$(dirname "$0")/.."

echo "== python: ruff"
uv run -q ruff check api
uv run -q ruff format --check -q api
echo "== python: pytest"
uv run -q pytest -q
echo "== web: svelte-check"
(cd web && npm run -s check)
echo "== web: vitest"
(cd web && npm test --silent)
echo "== web: end-to-end (Playwright)"
(cd web && npx playwright test --reporter=dot)
echo "== app: dart format, flutter analyze"
(cd app && dart format -o none --set-exit-if-changed lib test >/dev/null && flutter analyze --no-pub)
echo "== app: flutter test"
(cd app && flutter test --no-pub -r failures-only)
echo "== all checks passed"
