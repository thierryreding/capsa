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
    with engine.connect() as conn:
        sqlite = conn.dialect.name == "sqlite"
        if sqlite:
            # SQLite changes tables by rebuilding them (copy, DROP, rename). With foreign
            # keys enforced, the DROP would cascade and delete sessions, grants, settings
            # and events. The pragma only works outside a transaction, hence here.
            conn.exec_driver_sql("PRAGMA foreign_keys=OFF")
        _run(conn)
        conn.commit()
        if sqlite:
            problems = conn.exec_driver_sql("PRAGMA foreign_key_check").all()
            if problems:
                raise RuntimeError(f"foreign key violations after migration: {problems[:5]}")
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
