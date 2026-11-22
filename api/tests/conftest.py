from __future__ import annotations

import copy
from dataclasses import dataclass
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from capsa import accounts
from capsa.app import create_app
from capsa.config import Settings
from capsa.db import make_engine
from capsa.migrate import upgrade
from capsa.passwords import Passwords
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


# --- API fixtures -----------------------------------------------------------


CSRF = {"X-Capsa-CSRF": "1"}
PASSWORD = "geheim123"


class FakeClock:
    def __init__(self, start: int = 1_800_000_000_000):
        self.now = start

    def __call__(self) -> int:
        return self.now

    def advance(self, ms: int) -> None:
        self.now += ms


@dataclass
class Api:
    app: object
    clock: FakeClock
    engine: object
    passwords: Passwords

    def client(self) -> TestClient:
        # https so that Secure cookies are sent back, as in production
        return TestClient(self.app, base_url="https://capsa.test", headers=CSRF)

    def add_user(self, username: str, role: str = "learner", profiles=()):
        with self.engine.begin() as conn:
            user = accounts.create_user(
                conn, self.passwords, username, PASSWORD, role, self.clock()
            )
            accounts.set_grants(conn, user.id, set(profiles), self.clock())
        return user

    def login(self, username: str, password: str = PASSWORD) -> TestClient:
        c = self.client()
        r = c.post("/api/v1/auth/login", json={"username": username, "password": password})
        assert r.status_code == 200, r.text
        return c


@pytest.fixture
def api(tmp_path) -> Api:
    url = f"sqlite:///{tmp_path / 'capsa.sqlite'}"
    upgrade(url)
    engine = make_engine(url)
    settings = Settings(database_url=url, profile_dir=REPO / "profiles" / "demo")
    clock = FakeClock()
    passwords = Passwords.cheap()
    app = create_app(settings, engine=engine, passwords=passwords, clock=clock)
    yield Api(app, clock, engine, passwords)
    engine.dispose()
