"""FastAPI application. Everything is served under /api/v1 (SPEC section 5).

Run with `uvicorn --factory capsa.app:create_app`; configuration comes from CAPSA_*
environment variables (capsa.config).
"""

from __future__ import annotations

from importlib.metadata import version

from fastapi import APIRouter, FastAPI, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import Engine

from capsa.clock import Clock, now_ms
from capsa.config import Settings
from capsa.db import make_engine
from capsa.deps import CSRF_HEADER, AppState
from capsa.passwords import Passwords
from capsa.profiles import ProfileStore
from capsa.ratelimit import LoginLimiter
from capsa.routes import admin, auth, profiles, sync
from capsa.routes import settings as settings_routes

API_PREFIX = "/api/v1"
SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


class Health(BaseModel):
    status: str
    version: str


def create_app(
    settings: Settings | None = None,
    *,
    engine: Engine | None = None,
    passwords: Passwords | None = None,
    clock: Clock = now_ms,
) -> FastAPI:
    settings = settings or Settings.from_env()
    app = FastAPI(
        title="Capsa API",
        version=version("capsa"),
        openapi_url=f"{API_PREFIX}/openapi.json",
        docs_url=f"{API_PREFIX}/docs",
        redoc_url=None,
    )
    app.state.capsa = AppState(
        settings=settings,
        engine=engine or make_engine(settings.database_url),
        passwords=passwords or Passwords(),
        clock=clock,
        limiter=LoginLimiter(settings.login_max_failures, settings.login_window_seconds * 1000),
        profiles=ProfileStore(settings.profile_dir),
    )

    @app.middleware("http")
    async def require_csrf_header(request: Request, call_next):
        # Browsers cannot add custom headers to cross-site requests without a CORS
        # preflight, which this API never grants; together with SameSite=Strict
        # cookies this blocks cross-site request forgery (SPEC 8).
        if request.method not in SAFE_METHODS and request.headers.get(CSRF_HEADER) != "1":
            return JSONResponse(
                {"detail": f"missing {CSRF_HEADER} header"}, status.HTTP_403_FORBIDDEN
            )
        return await call_next(request)

    router = APIRouter(prefix=API_PREFIX)

    @router.get("/health", tags=["meta"])
    def health() -> Health:
        """Liveness check for the container runtime and the reverse proxy."""
        return Health(status="ok", version=app.version)

    router.include_router(auth.router)
    router.include_router(profiles.router)
    router.include_router(sync.router)
    router.include_router(settings_routes.router)
    router.include_router(admin.router)
    app.include_router(router)
    return app
