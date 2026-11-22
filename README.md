# Capsa

Self-hosted vocabulary trainer (offline PWA built with Svelte, API with sync), with one profile per language and textbook.
Specification: [SPEC.md](SPEC.md). Status: M0 (foundations).

## Layout

| Path | Contents |
|---|---|
| `schemas/profile.schema.json` | Authoritative JSON Schema for profiles |
| `api/` | Python package `capsa`: `capsa` CLI and profile validation, later the FastAPI server |
| `web/` | Frontend. For now only the answer-checking logic in `src/lib/learning/` (TypeScript) |
| `vectors/` | Shared JSON test vectors for the learning logic |
| `profiles/demo/` | Self-written demo profile used by tests and examples |

## Development

```sh
# Python: validation and CLI
cd api && uv sync
uv run pytest
uv run capsa validate ../profiles/demo/demo-latin.yaml

# TypeScript: answer checking
cd web && npm install
npm test
npm run check
```

## Private profile

`profiles/private/` is excluded via `.gitignore`. It holds `latein-lehrbuch.yaml`, which contains textbook content.
Check it with `cd api && uv run capsa validate ../profiles/private/latein-lehrbuch.yaml`.
Both test suites also run content-free property checks against any private profile that is present, and skip them otherwise.

## Licence

AGPL-3.0-or-later, see [LICENSE](LICENSE).
