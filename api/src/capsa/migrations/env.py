"""Alembic environment. Configured programmatically by capsa.migrate (no alembic.ini)."""

from alembic import context

from capsa.db import make_engine, metadata

config = context.config


def run_migrations() -> None:
    connection = config.attributes.get("connection")
    if connection is not None:
        _run(connection)
        return
    engine = make_engine(config.get_main_option("sqlalchemy.url"))
    with engine.begin() as conn:
        _run(conn)
    engine.dispose()


def _run(connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=metadata,
        render_as_batch=True,  # SQLite needs batch mode for ALTER TABLE
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


run_migrations()
