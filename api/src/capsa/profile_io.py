"""Loading profile files. This is the only module here that touches the file system."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


class DuplicateKeyError(yaml.YAMLError):
    pass


class _StrictLoader(yaml.SafeLoader):
    """SafeLoader that rejects duplicate mapping keys instead of silently keeping the last one."""


def _construct_mapping(loader: _StrictLoader, node: yaml.MappingNode, deep: bool = False) -> dict:
    loader.flatten_mapping(node)
    seen: set[Any] = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            mark = key_node.start_mark
            raise DuplicateKeyError(
                f"duplicate key {key!r} at line {mark.line + 1}, column {mark.column + 1}"
            )
        seen.add(key)
    return loader.construct_mapping(node, deep=deep)


_StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


def parse_profile(text: str) -> Any:
    return yaml.load(text, Loader=_StrictLoader)  # noqa: S506 - SafeLoader subclass


def load_profile(path: str | Path) -> Any:
    return parse_profile(Path(path).read_text(encoding="utf-8"))
