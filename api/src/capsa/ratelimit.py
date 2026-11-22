"""In-memory rate limiting for login attempts (SPEC 8).

Counts failed attempts per (client, username) and per client within a sliding
window. Single-process only, which matches the single API container.
"""

from __future__ import annotations

from collections import defaultdict, deque
from threading import Lock

# A client may fail this many times more in total than per username, to slow down
# guessing across many accounts while not locking out a family behind one NAT address.
PER_CLIENT_FACTOR = 4


class LoginLimiter:
    def __init__(self, max_failures: int, window_ms: int):
        self.max_failures = max_failures
        self.window_ms = window_ms
        self._failures: dict[tuple[str, ...], deque[int]] = defaultdict(deque)
        self._lock = Lock()

    def _prune(self, key: tuple[str, ...], now: int) -> deque[int]:
        q = self._failures[key]
        while q and q[0] <= now - self.window_ms:
            q.popleft()
        if not q:
            del self._failures[key]
        return q

    def retry_after_ms(self, client: str, username: str, now: int) -> int:
        """0 if an attempt is allowed, otherwise milliseconds until the next one is."""
        with self._lock:
            waits = []
            for key, limit in self._limits(client, username):
                q = self._prune(key, now)
                if len(q) >= limit:
                    waits.append(q[len(q) - limit] + self.window_ms - now)
            return max(waits, default=0)

    def failed(self, client: str, username: str, now: int) -> None:
        with self._lock:
            for key, _ in self._limits(client, username):
                self._failures[key].append(now)

    def succeeded(self, client: str, username: str) -> None:
        with self._lock:
            self._failures.pop(("user", client, username), None)

    def _limits(self, client: str, username: str) -> list[tuple[tuple[str, ...], int]]:
        return [
            (("user", client, username), self.max_failures),
            (("client", client), self.max_failures * PER_CLIENT_FACTOR),
        ]
