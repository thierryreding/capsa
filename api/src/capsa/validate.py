"""Profile validation: JSON Schema plus cross-reference rules.

Pure functions over already-parsed profile data. Messages name IDs and paths only,
never profile text, so output from private profiles can be shared safely.
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from functools import cache
from importlib import resources
from typing import Any, Literal

from jsonschema import Draft202012Validator

Level = Literal["error", "warning"]


@dataclass(frozen=True)
class Issue:
    level: Level
    path: str
    message: str
    code: str = ""

    def __str__(self) -> str:
        code = f" [{self.code}]" if self.code else ""
        return f"{self.level}: {self.path or '<root>'}: {self.message}{code}"


@cache
def profile_schema() -> dict[str, Any]:
    text = resources.files("capsa").joinpath("schemas/profile.schema.json").read_text("utf-8")
    return json.loads(text)


def _path(parts: Iterable[Any]) -> str:
    out = ""
    for p in parts:
        out += f"[{p}]" if isinstance(p, int) else (f".{p}" if out else str(p))
    return out


def _error(path: str, message: str) -> Issue:
    return Issue("error", path, message)


def _warning(path: str, message: str) -> Issue:
    return Issue("warning", path, message)


def schema_issues(data: Any) -> list[Issue]:
    validator = Draft202012Validator(profile_schema())
    errors = sorted(validator.iter_errors(data), key=lambda e: list(map(str, e.absolute_path)))
    return [_error(_path(e.absolute_path), _schema_message(e)) for e in errors]


def _schema_message(err: Any) -> str:
    # jsonschema messages embed the offending value; keep only the rule for long strings.
    if err.validator in {"additionalProperties", "required", "enum", "const", "type"}:
        return err.message
    return f"violates '{err.validator}' ({err.validator_value!r})"


def semantic_issues(data: dict[str, Any]) -> Iterator[Issue]:
    """Cross-reference checks. Assumes `data` already passed the schema."""
    profile = data["profile"]
    source = profile["source_lang"]
    required = profile["required_translation_lang"]
    tr_langs = set(profile["translation_langs"])
    text_langs = tr_langs | {source}

    if required not in tr_langs:
        yield _error("profile.required_translation_lang", "must be listed in translation_langs")
    if source in tr_langs:
        yield _warning("profile.translation_langs", "contains the source language")

    for key, mapping in profile.get("matching", {}).items():
        if isinstance(mapping, dict):
            for lang in mapping:
                if lang not in text_langs:
                    yield _error(f"profile.matching.{key}.{lang}", "unknown language")

    unit_ids: set[str] = set()
    unit_numbers: set[int] = set()
    table_ids: set[str] = set()
    entry_unit: dict[str, int] = {}  # entry id -> unit number
    deprecated: set[str] = set()
    last_number = -1

    for ui, unit in enumerate(data["units"]):
        upath = f"units[{ui}]"
        uid, number = unit["id"], unit["number"]
        if uid in unit_ids:
            yield _error(f"{upath}.id", f"duplicate unit id '{uid}'")
        unit_ids.add(uid)
        if number in unit_numbers:
            yield _error(f"{upath}.number", f"duplicate unit number {number}")
        unit_numbers.add(number)
        if number < last_number:
            yield _warning(f"{upath}.number", "units are not in ascending order")
        last_number = max(last_number, number)

        for ti, table in enumerate(unit.get("tables", [])):
            if table["id"] in table_ids:
                yield _error(f"{upath}.tables[{ti}].id", f"duplicate table id '{table['id']}'")
            table_ids.add(table["id"])
            width = len(table["columns"])
            for ri, row in enumerate(table["rows"]):
                if len(row) != width:
                    yield _error(
                        f"{upath}.tables[{ti}].rows[{ri}]",
                        f"has {len(row)} cells, expected {width}",
                    )

        for ei, entry in enumerate(unit["entries"]):
            epath = f"{upath}.entries[{ei}]"
            eid = entry["id"]
            if eid in entry_unit:
                yield _error(f"{epath}.id", f"duplicate entry id '{eid}'")
            entry_unit[eid] = number
            if entry.get("deprecated"):
                deprecated.add(eid)
            if not eid.startswith(uid + "-"):
                yield _warning(f"{epath}.id", f"'{eid}' does not start with unit id '{uid}-'")

            tr = entry["tr"]
            if not entry.get("deprecated") and not tr.get(required):
                yield _error(f"{epath}.tr", f"'{eid}' lacks required translation '{required}'")
            for lang in tr:
                if lang not in tr_langs:
                    yield _error(f"{epath}.tr.{lang}", "language not in translation_langs")
            for xi, example in enumerate(entry.get("examples", [])):
                if source not in example:
                    yield _error(f"{epath}.examples[{xi}]", f"missing source text '{source}'")
                for lang in example:
                    if lang not in text_langs:
                        yield _error(f"{epath}.examples[{xi}].{lang}", "unknown language")

    for ui, unit in enumerate(data["units"]):
        for ri, ref in enumerate(unit.get("review", [])):
            rpath = f"units[{ui}].review[{ri}]"
            if ref not in entry_unit:
                yield _error(rpath, f"unknown entry '{ref}'")
            elif entry_unit[ref] >= unit["number"]:
                yield _error(rpath, f"'{ref}' is not from an earlier unit")
            elif ref in deprecated:
                yield _warning(rpath, f"'{ref}' is deprecated")


def validate_profile(data: Any) -> list[Issue]:
    issues = schema_issues(data)
    if issues:
        return issues
    return list(semantic_issues(data))


def summary(data: dict[str, Any]) -> dict[str, int]:
    """Entry counts per unit id (for CLI output)."""
    return {u["id"]: len(u["entries"]) for u in data["units"]}
