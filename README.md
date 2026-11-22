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
# Python (uv workspace, run from the repository root)
uv sync
uv run pytest
uv run capsa validate profiles/demo/demo-latin.yaml
uv run capsa lint profiles/demo/demo-latin.yaml         # validation plus warnings
uv run capsa import-csv words.csv -o words.yaml \
    --id my-words --title "My words" --source-lang la --tr-lang de
uv run ruff check api && uv run ruff format --check api

# TypeScript: answer checking
cd web && npm install
npm test
npm run check
```

`import-csv` expects the columns `unit;lemma;info;translation` (header optional, UTF-8). Several
meanings are separated by `,` or `;` outside parentheses; quote the field if it contains `;`.

## Local test pod

`deploy/local/` runs the API behind Traefik in a podman pod, for testing the proxy setup locally:

```sh
deploy/local/pod.sh up        # build the API image, start the pod, wait until healthy
curl http://capsa.localhost:8080/api/v1/health
deploy/local/pod.sh logs      # follow all container logs
deploy/local/pod.sh down
```

HTTPS is on `https://capsa.localhost:8443` (self-signed), the Traefik dashboard on
`http://localhost:8081/dashboard/`. Image builds use the repository root as context;
`.containerignore` keeps `profiles/private/` out of every image.

## Private profile

`profiles/private/` is excluded via `.gitignore`. It holds `latein-lehrbuch.yaml`, which contains textbook content.
Check it with `uv run capsa lint profiles/private/latein-lehrbuch.yaml`.
Both test suites also run content-free property checks against any private profile that is present, and skip them otherwise.

## Licence

AGPL-3.0-or-later, see [LICENSE](LICENSE).
