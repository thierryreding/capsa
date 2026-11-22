"""FastAPI application. Everything is served under /api/v1 (SPEC section 5)."""

from __future__ import annotations

from importlib.metadata import version

from fastapi import APIRouter, FastAPI
from pydantic import BaseModel

API_PREFIX = "/api/v1"


class Health(BaseModel):
    status: str
    version: str


def create_app() -> FastAPI:
    app = FastAPI(
        title="Capsa API",
        version=version("capsa"),
        openapi_url=f"{API_PREFIX}/openapi.json",
        docs_url=f"{API_PREFIX}/docs",
        redoc_url=None,
    )
    router = APIRouter(prefix=API_PREFIX)

    @router.get("/health", tags=["meta"])
    def health() -> Health:
        """Liveness check for the container runtime and the reverse proxy."""
        return Health(status="ok", version=app.version)

    app.include_router(router)
    return app


app = create_app()
