from __future__ import annotations

import copy
from pathlib import Path

import pytest

from capsa.profile_io import load_profile

REPO = Path(__file__).resolve().parents[2]
DEMO_PROFILE = REPO / "profiles" / "demo" / "demo-latin.yaml"
PRIVATE_DIR = REPO / "profiles" / "private"


@pytest.fixture(scope="session")
def _demo_pristine() -> dict:
    return load_profile(DEMO_PROFILE)


@pytest.fixture
def demo(_demo_pristine) -> dict:
    """A fresh, mutable copy of the demo profile."""
    return copy.deepcopy(_demo_pristine)


def private_profiles() -> list[Path]:
    return sorted(PRIVATE_DIR.glob("*.yaml")) if PRIVATE_DIR.is_dir() else []
