# Capsa

Self-hosted vocabulary trainer (offline PWA built with Svelte, API with sync), with one profile per language and textbook.
Specification: [SPEC.md](SPEC.md). Status: planning, no code yet.

## Private profile

`profiles/private/` is excluded via `.gitignore`. It holds `latein-lehrbuch.yaml`, which contains textbook content.
Check it with: `python3 -I tools/check_profile.py profiles/private/latein-lehrbuch.yaml`

Software licence: AGPL-3.0 (add the LICENSE file when creating the repository).
