"""Password policy and hashing (argon2id, SPEC 8)."""

from __future__ import annotations

from functools import cached_property

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

MIN_LENGTH = 8
MAX_LENGTH = 1024  # bounds hashing work per request


class PasswordPolicyError(ValueError):
    pass


def check_policy(password: str) -> None:
    """At least MIN_LENGTH characters; no composition rules (NIST SP 800-63B)."""
    if len(password) < MIN_LENGTH:
        raise PasswordPolicyError(f"password must have at least {MIN_LENGTH} characters")
    if len(password) > MAX_LENGTH:
        raise PasswordPolicyError(f"password must have at most {MAX_LENGTH} characters")


class Passwords:
    """argon2id hashing. The defaults of argon2-cffi follow RFC 9106 (64 MiB, t=3, p=4);
    tests pass cheaper parameters."""

    def __init__(self, hasher: PasswordHasher | None = None):
        self.hasher = hasher or PasswordHasher()

    @classmethod
    def cheap(cls) -> Passwords:
        """Fast parameters for tests only."""
        return cls(PasswordHasher(time_cost=1, memory_cost=8, parallelism=1))

    def hash(self, password: str) -> str:
        check_policy(password)
        return self.hasher.hash(password)

    def verify(self, password_hash: str, password: str) -> bool:
        if len(password) > MAX_LENGTH:
            return False
        try:
            return self.hasher.verify(password_hash, password)
        except (VerificationError, InvalidHashError):
            return False

    def needs_rehash(self, password_hash: str) -> bool:
        return self.hasher.check_needs_rehash(password_hash)

    @cached_property
    def _dummy_hash(self) -> str:
        return self.hasher.hash("dummy password for timing")

    def burn(self, password: str) -> None:
        """Spend the same time as a real check when the user does not exist."""
        self.verify(self._dummy_hash, password)
