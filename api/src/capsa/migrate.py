"""Run database migrations (Alembic) from code."""

from __future__ import annotations

from importlib import resources

from alembic import command
from alembic.config import Config


def alembic_config(database_url: str) -> Config:
    cfg = Config()
    cfg.set_main_option("script_location", str(resources.files("capsa") / "migrations"))
    cfg.set_main_option("sqlalchemy.url", database_url)
    return cfg


def upgrade(database_url: str, revision: str = "head") -> None:
    command.upgrade(alembic_config(database_url), revision)


def revision(database_url: str, message: str) -> None:
    """Developer helper: autogenerate a new migration against an up-to-date database."""
    command.revision(alembic_config(database_url), message=message, autogenerate=True)
