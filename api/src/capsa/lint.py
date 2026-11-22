"""Profile lint: warnings about likely mistakes that are not hard errors.

Pure functions over profile data that has already passed `validate_profile`.
Unlike validation, lint messages quote the words concerned, because that is what
makes them actionable; they are meant for the profile author's terminal only.
"""

from __future__ import annotations

import re
import unicodedata
from collections import defaultdict
from collections.abc import Iterator
from typing import Any

from capsa.validate import Issue

_WORD = re.compile(r"\w+")
_INFO_FORM_EXCLUDE = re.compile(r"[.+]")


def strip_marks(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))


def _key(text: str) -> str:
    return strip_marks(text).casefold().strip(" !?.")


def _lint(path: str, code: str, message: str) -> Issue:
    return Issue("warning", path, message, code)


def info_forms(entry: dict[str, Any]) -> list[str]:
    """Same heuristic as the client's `infoForms` (web/src/lib/learning/match.ts)."""
    info = (entry.get("info") or "").strip()
    pos = entry.get("pos")
    if not info or (pos is not None and pos != "verb"):
        return []
    if pos is None and _INFO_FORM_EXCLUDE.search(info):
        return []
    return [f.strip() for f in re.split(r"[,;]", info) if f.strip()]


def _entries(data: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any]]]:
    for ui, unit in enumerate(data["units"]):
        for ei, entry in enumerate(unit["entries"]):
            if not entry.get("deprecated"):
                yield f"units[{ui}].entries[{ei}]", entry


def _strings(node: Any, path: str) -> Iterator[tuple[str, str]]:
    if isinstance(node, str):
        yield path, node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield from _strings(v, f"{path}.{k}" if path else str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from _strings(v, f"{path}[{i}]")


def check_whitespace(data: dict[str, Any]) -> Iterator[Issue]:
    for path, text in _strings(data, ""):
        if text != text.strip() and not path.startswith("profile.matching"):
            yield _lint(path, "whitespace", "leading or trailing whitespace")
        elif "  " in text:
            yield _lint(path, "whitespace", "repeated spaces")


def check_matching_prefixes(data: dict[str, Any]) -> Iterator[Issue]:
    matching = data["profile"].get("matching", {})
    for key in ("strip_prefixes", "optional_articles", "optional_words"):
        for lang, items in matching.get(key, {}).items():
            for i, item in enumerate(items):
                if item != item.strip():
                    yield _lint(
                        f"profile.matching.{key}.{lang}[{i}]",
                        "matching-space",
                        f"{item!r}: surrounding whitespace is not needed, "
                        "prefixes match at word boundaries",
                    )


def check_duplicate_lemmas(data: dict[str, Any]) -> Iterator[Issue]:
    seen: dict[str, str] = {}
    for path, entry in _entries(data):
        key = _key(entry["lemma"])
        if key in seen:
            yield _lint(
                f"{path}.lemma",
                "duplicate-lemma",
                f"'{entry['id']}' has the same lemma as '{seen[key]}' ({entry['lemma']!r})",
            )
        else:
            seen[key] = entry["id"]


def check_meanings(data: dict[str, Any]) -> Iterator[Issue]:
    for path, entry in _entries(data):
        for lang, meanings in entry["tr"].items():
            keys = [_key(m) for m in meanings]
            for i, (meaning, key) in enumerate(zip(meanings, keys, strict=True)):
                mpath = f"{path}.tr.{lang}[{i}]"
                if key in keys[:i]:
                    yield _lint(mpath, "duplicate-meaning", f"{meaning!r} is listed twice")
                if ";" in meaning:
                    yield _lint(
                        mpath,
                        "combined-meanings",
                        f"{meaning!r}: split at ';' into separate meanings",
                    )


def check_macrons(data: dict[str, Any]) -> Iterator[Issue]:
    """Source-language words spelled with different macrons/diacritics.

    Lemmas and info forms must agree exactly. In example sentences, only a difference
    before the last letter counts, since endings legitimately differ (puella / puellā).
    Only identical word forms are compared; inflected forms are not related to the lemma.
    """
    source = data["profile"]["source_lang"]
    spellings: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    headwords: dict[str, set[str]] = defaultdict(set)  # spellings seen in lemma/info

    for _path, entry in _entries(data):
        for text in [entry["lemma"], *info_forms(entry)]:
            for word in _WORD.findall(text):
                key, spelled = strip_marks(word).casefold(), word.casefold()
                spellings[key][spelled].append(entry["id"])
                headwords[key].add(spelled)
        for example in entry.get("examples", []):
            for word in _WORD.findall(example.get(source, "")):
                spellings[strip_marks(word).casefold()][word.casefold()].append(entry["id"])

    for key, variants in spellings.items():
        if len(variants) < 2:
            continue
        stems_differ = len({v[:-1] for v in variants}) > 1
        if len(headwords.get(key, ())) < 2 and not stems_differ:
            continue
        ids = sorted({i for users in variants.values() for i in users})
        yield _lint(
            "units",
            "macron-variant",
            f"spelled {' / '.join(sorted(variants))} in {', '.join(ids)}",
        )


def check_empty_units(data: dict[str, Any]) -> Iterator[Issue]:
    for ui, unit in enumerate(data["units"]):
        if not any(not e.get("deprecated") for e in unit["entries"]):
            yield _lint(f"units[{ui}]", "empty-unit", f"unit '{unit['id']}' has no active entries")


CHECKS = (
    check_whitespace,
    check_matching_prefixes,
    check_duplicate_lemmas,
    check_meanings,
    check_macrons,
    check_empty_units,
)


def lint_profile(data: dict[str, Any]) -> list[Issue]:
    return [issue for check in CHECKS for issue in check(data)]
