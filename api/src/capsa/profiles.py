"""Profiles served by the API: loaded from YAML files, validated, kept in memory.

The folder is re-scanned when files change (cheap: one stat per file), so updated
profiles are picked up without a restart. Invalid profiles are skipped and logged
with their path and error count only, never their content.
"""

from __future__ import annotations

import hashlib
import json
import logging
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from typing import Any

import yaml

from capsa.profile_io import load_profile
from capsa.validate import validate_profile

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class LoadedProfile:
    id: str
    title: str
    source_lang: str
    required_translation_lang: str
    translation_langs: tuple[str, ...]
    revision: int
    body: bytes
    """The profile document as UTF-8 JSON, exactly as served."""
    etag: str
    entry_ids: frozenset[str]
    path: Path


def build(path: Path, data: dict[str, Any]) -> LoadedProfile:
    p = data["profile"]
    body = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode()
    return LoadedProfile(
        id=p["id"],
        title=p["title"],
        source_lang=p["source_lang"],
        required_translation_lang=p["required_translation_lang"],
        translation_langs=tuple(p["translation_langs"]),
        revision=p["revision"],
        body=body,
        etag='"' + hashlib.sha256(body).hexdigest()[:32] + '"',
        entry_ids=frozenset(e["id"] for u in data["units"] for e in u["entries"]),
        path=path,
    )


class ProfileStore:
    def __init__(self, directory: Path):
        self.directory = directory
        self._lock = Lock()
        self._signature: tuple[tuple[str, int, int], ...] | None = None
        self._profiles: dict[str, LoadedProfile] = {}

    def _files(self) -> list[Path]:
        if not self.directory.is_dir():
            return []
        return sorted(p for pattern in ("*.yaml", "*.yml") for p in self.directory.rglob(pattern))

    def _scan_signature(self, files: list[Path]) -> tuple[tuple[str, int, int], ...]:
        sig = []
        for f in files:
            try:
                st = f.stat()
            except OSError:
                continue
            sig.append((str(f), st.st_mtime_ns, st.st_size))
        return tuple(sig)

    def refresh(self) -> None:
        files = self._files()
        signature = self._scan_signature(files)
        with self._lock:
            if signature == self._signature:
                return
            self._profiles = self._load(files)
            self._signature = signature

    def _load(self, files: list[Path]) -> dict[str, LoadedProfile]:
        loaded: dict[str, LoadedProfile] = {}
        for path in files:
            try:
                data = load_profile(path)
            except (OSError, yaml.YAMLError):
                log.error("profile %s: cannot be loaded, skipped", path)
                continue
            errors = [i for i in validate_profile(data) if i.level == "error"]
            if errors:
                log.error("profile %s: %d validation errors, skipped", path, len(errors))
                continue
            profile = build(path, data)
            if profile.id in loaded:
                log.error(
                    "profile %s: id '%s' already loaded from %s, skipped",
                    path,
                    profile.id,
                    loaded[profile.id].path,
                )
                continue
            loaded[profile.id] = profile
        log.info("loaded %d profiles from %s", len(loaded), self.directory)
        return loaded

    def all(self) -> list[LoadedProfile]:
        self.refresh()
        return sorted(self._profiles.values(), key=lambda p: p.id)

    def get(self, profile_id: str) -> LoadedProfile | None:
        self.refresh()
        return self._profiles.get(profile_id)
