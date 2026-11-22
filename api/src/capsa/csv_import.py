"""Create a profile from simple CSV rows: `unit;lemma;info;translation`.

Pure functions; the CLI does the file handling. The result is a starting point that
the author completes by hand (unit titles, notes, examples, further languages).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from capsa.lint import strip_marks

COLUMNS = ("unit", "lemma", "info", "translation")


@dataclass(frozen=True)
class ProfileMeta:
    id: str
    title: str
    source_lang: str
    translation_lang: str


class CsvImportError(ValueError):
    """Raised with all problems found in the input, one per line."""

    def __init__(self, problems: list[str]):
        super().__init__("\n".join(problems))
        self.problems = problems


def slug(text: str) -> str:
    s = strip_marks(text).casefold()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "entry"


def split_meanings(text: str) -> list[str]:
    """Split at ',' or ';' outside parentheses: 'da (zeitlich, örtlich), dann' -> 2 meanings."""
    parts: list[str] = []
    depth = 0
    current = ""
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        if ch in ",;" and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    parts.append(current)
    return [" ".join(p.split()) for p in parts if p.strip()]


def _is_header(row: list[str]) -> bool:
    return [c.strip().casefold() for c in row[: len(COLUMNS)]] == list(COLUMNS)


def rows_to_profile(rows: list[list[str]], meta: ProfileMeta) -> dict[str, Any]:
    """Build profile data from CSV rows. Row numbers in errors are 1-based file lines."""
    problems: list[str] = []
    units: dict[int, dict[str, Any]] = {}
    used_ids: set[str] = set()

    for lineno, row in enumerate(rows, start=1):
        if not any(c.strip() for c in row):
            continue
        if lineno == 1 and _is_header(row):
            continue
        if len(row) != len(COLUMNS):
            problems.append(f"line {lineno}: expected {len(COLUMNS)} columns, got {len(row)}")
            continue
        unit_s, lemma, info, translation = (" ".join(c.split()) for c in row)
        if not unit_s.isdigit():
            problems.append(f"line {lineno}: unit must be a number, got {unit_s!r}")
            continue
        if not lemma:
            problems.append(f"line {lineno}: lemma is empty")
            continue
        meanings = split_meanings(translation)
        if not meanings:
            problems.append(f"line {lineno}: translation is empty")
            continue

        number = int(unit_s)
        unit = units.setdefault(
            number,
            {"id": f"u{number}", "number": number, "title": f"Unit {number}", "entries": []},
        )
        base = f"{unit['id']}-{slug(lemma)}"
        entry_id, n = base, 1
        while entry_id in used_ids:
            n += 1
            entry_id = f"{base}-{n}"
        used_ids.add(entry_id)

        entry: dict[str, Any] = {"id": entry_id, "lemma": lemma}
        if info:
            entry["info"] = info
        entry["tr"] = {meta.translation_lang: meanings}
        unit["entries"].append(entry)

    if problems:
        raise CsvImportError(problems)
    if not units:
        raise CsvImportError(["no entries found"])

    return {
        "schema_version": 1,
        "profile": {
            "id": meta.id,
            "title": meta.title,
            "source_lang": meta.source_lang,
            "required_translation_lang": meta.translation_lang,
            "translation_langs": [meta.translation_lang],
            "note_langs": [meta.translation_lang],
            "revision": 1,
            "rights": {"content": "own", "distribution": "private-use-only"},
            "matching": {"ignore_diacritics": True},
        },
        "units": [units[k] for k in sorted(units)],
    }
