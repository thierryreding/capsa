"""The `capsa` command line tool (Click)."""

from __future__ import annotations

import csv
import json
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

import click
import yaml
from sqlalchemy import Connection
from sqlalchemy.engine import make_url

from capsa import accounts, migrate
from capsa.accounts import AccountError
from capsa.app import create_app
from capsa.backup import BackupError, backup
from capsa.clock import now_ms, to_datetime
from capsa.config import Settings
from capsa.csv_import import CsvImportError, ProfileMeta, rows_to_profile
from capsa.db import make_engine
from capsa.lint import lint_profile
from capsa.passwords import PasswordPolicyError, Passwords
from capsa.profile_io import dump_profile, load_profile
from capsa.stats import SNAPSHOT_THRESHOLD, sqlite_size, usage
from capsa.validate import Issue, summary, validate_profile


def fail() -> None:
    raise click.exceptions.Exit(1)


def err(message: str) -> None:
    click.echo(message, err=True)


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
def cli() -> None:
    """Capsa vocabulary trainer tools."""


# --- profiles ---------------------------------------------------------------


def _check_files(
    paths: Sequence[str], strict: bool, extra: Callable[[Any], list[Issue]] | None = None
) -> None:
    """Validate each profile (and run `extra` checks on valid ones); print a report."""
    failed = False
    for path in paths:
        try:
            data = load_profile(path)
        except (OSError, yaml.YAMLError) as exc:
            err(f"{path}: cannot load: {exc}")
            failed = True
            continue

        issues = validate_profile(data)
        errors = [i for i in issues if i.level == "error"]
        if not errors and extra is not None:
            issues += extra(data)
        warnings = [i for i in issues if i.level == "warning"]
        for issue in issues:
            click.echo(f"{path}: {issue}")
        if errors or (strict and warnings):
            failed = True
            status = "FAILED"
        else:
            status = "ok"
        counts = summary(data) if not errors else {}
        detail = f"{len(counts)} units, {sum(counts.values())} entries, " if counts else ""
        click.echo(f"{path}: {status} ({detail}{len(errors)} errors, {len(warnings)} warnings)")
    if failed:
        fail()


profiles_argument = click.argument("profiles", nargs=-1, required=True, metavar="PROFILE...")
strict_option = click.option("--strict", is_flag=True, help="Treat warnings as errors.")


@cli.command()
@profiles_argument
@strict_option
def validate(profiles: tuple[str, ...], strict: bool) -> None:
    """Check profiles against the schema and reference rules."""
    _check_files(profiles, strict)


@cli.command()
@profiles_argument
@strict_option
def lint(profiles: tuple[str, ...], strict: bool) -> None:
    """Validate, then warn about likely mistakes."""
    _check_files(profiles, strict, extra=lint_profile)


@cli.command("import-csv")
@click.argument("csv_path", metavar="CSV")
@click.option("-o", "--output", required=True, help="Profile file to write, '-' for stdout.")
@click.option("--id", "profile_id", required=True, help="Profile id, e.g. latin-own-words.")
@click.option("--title", required=True)
@click.option("--source-lang", required=True, help="Language of the lemmas, e.g. la.")
@click.option("--tr-lang", required=True, help="Language of the translations, e.g. de.")
@click.option("--delimiter", default=";", show_default=True, help="Column separator.")
@click.option("--force", is_flag=True, help="Overwrite an existing output file.")
def import_csv(
    csv_path: str,
    output: str,
    profile_id: str,
    title: str,
    source_lang: str,
    tr_lang: str,
    delimiter: str,
    force: bool,
) -> None:
    """Create a profile from a CSV file (unit;lemma;info;translation)."""
    out = Path(output)
    if output != "-" and out.exists() and not force:
        err(f"{out}: exists, use --force to overwrite")
        fail()
    try:
        with open(csv_path, encoding="utf-8-sig", newline="") as f:
            rows = list(csv.reader(f, delimiter=delimiter))
    except OSError as exc:
        err(f"{csv_path}: cannot read: {exc}")
        fail()

    meta = ProfileMeta(
        id=profile_id, title=title, source_lang=source_lang, translation_lang=tr_lang
    )
    try:
        data = rows_to_profile(rows, meta)
    except CsvImportError as exc:
        for problem in exc.problems:
            err(f"{csv_path}: {problem}")
        fail()

    errors = [i for i in validate_profile(data) if i.level == "error"]
    if errors:
        for issue in errors:
            err(f"{csv_path}: {issue}")
        fail()

    text = dump_profile(data)
    if output == "-":
        click.echo(text, nl=False)
    else:
        out.write_text(text, encoding="utf-8")
        counts = summary(data)
        click.echo(f"{out}: wrote {len(counts)} units, {sum(counts.values())} entries")


@cli.command()
@click.option("-o", "--output", default="-", help="File to write, '-' for stdout.")
def openapi(output: str) -> None:
    """Write the API description (OpenAPI JSON)."""
    text = json.dumps(create_app(Settings()).openapi(), indent=2, ensure_ascii=False) + "\n"
    if output == "-":
        click.echo(text, nl=False)
    else:
        Path(output).write_text(text, encoding="utf-8")


# --- database ---------------------------------------------------------------

database_option = click.option(
    "--database-url",
    envvar="CAPSA_DATABASE_URL",
    default=Settings().database_url,
    show_default=True,
    show_envvar=True,
    help="SQLAlchemy URL of the database.",
)


@cli.group()
def db() -> None:
    """Database maintenance."""


@db.command()
@database_option
def upgrade(database_url: str) -> None:
    """Apply all pending migrations."""
    migrate.upgrade(database_url)
    click.echo("database is up to date")


@db.command("backup")
@click.argument("directory", type=click.Path(file_okay=False, path_type=Path))
@click.option("--keep", default=14, show_default=True, help="Number of copies to keep.")
@database_option
def db_backup(directory: Path, keep: int, database_url: str) -> None:
    """Write a consistent copy of the database into DIRECTORY (safe while running)."""
    try:
        target = backup(database_url, directory, keep)
    except BackupError as exc:
        err(f"error: {exc}")
        fail()
    click.echo(f"backup written to {target}")


def _size(n: int | None) -> str:
    if n is None:
        return "n/a"
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return str(n)


@cli.command()
@click.option("--json", "as_json", is_flag=True, help="Machine-readable output.")
@database_option
def stats(as_json: bool, database_url: str) -> None:
    """Show usage: events per account, database size (for monitoring growth)."""
    url = make_url(database_url)
    size = sqlite_size(url.database) if url.get_backend_name() == "sqlite" else None
    engine = make_engine(database_url)
    try:
        with engine.connect() as conn:
            result = usage(conn, now_ms(), size)
    finally:
        engine.dispose()
    if as_json:
        click.echo(json.dumps(result.as_dict(), indent=2))
        return
    click.echo(
        f"database: {_size(result.database_bytes)}, {result.total_events} events, "
        f"{result.settings} settings, {result.sessions} sessions"
    )
    click.echo(
        f"{'account':<20} {'role':<8} {'events':>8} {'30 days':>8} {'devices':>8}  last answer"
    )
    for a in result.accounts:
        last = to_datetime(a.last_event_at).strftime("%Y-%m-%d %H:%M") if a.last_event_at else "-"
        click.echo(
            f"{a.username:<20} {a.role:<8} {a.events:>8} {a.events_30d:>8} {a.devices:>8}  {last}"
        )
    if result.over_threshold:
        click.echo(
            f"note: {', '.join(result.over_threshold)} passed {SNAPSHOT_THRESHOLD} events; "
            "time to consider learning-state snapshots (SPEC 13)."
        )


# --- accounts ---------------------------------------------------------------


def _transaction(database_url: str, fn: Callable[[Connection], str]) -> None:
    """Run `fn` in one transaction; print its result, or the error and fail."""
    engine = make_engine(database_url)
    try:
        with engine.begin() as conn:
            click.echo(fn(conn))
    except (AccountError, PasswordPolicyError) as exc:
        err(f"error: {exc}")
        fail()
    finally:
        engine.dispose()


def _read_password(from_stdin: bool) -> str:
    if from_stdin:
        return sys.stdin.readline().rstrip("\r\n")
    return click.prompt("New password", hide_input=True, confirmation_prompt="Repeat password")


password_stdin_option = click.option(
    "--password-stdin", is_flag=True, help="Read the password from stdin."
)


@cli.group()
def user() -> None:
    """Manage accounts."""


@user.command("add")
@click.argument("username")
@click.option("--admin", is_flag=True, help="Create an admin (parent) account.")
@click.option("--display-name", help="Name the app greets with (default: the username).")
@password_stdin_option
@database_option
def user_add(
    username: str, admin: bool, display_name: str | None, password_stdin: bool, database_url: str
) -> None:
    """Create an account (asks for the password)."""
    try:
        accounts.normalize_display_name(display_name)  # fail before asking for the password
    except AccountError as exc:
        err(f"error: {exc}")
        fail()
    password = _read_password(password_stdin)

    def run(conn: Connection) -> str:
        role = "admin" if admin else "learner"
        u = accounts.create_user(
            conn, Passwords(), username, password, role, now_ms(), display_name=display_name
        )
        return f"created {u.role} {u.username} ({u.id})"

    _transaction(database_url, run)


@user.command("passwd")
@click.argument("username")
@password_stdin_option
@database_option
def user_passwd(username: str, password_stdin: bool, database_url: str) -> None:
    """Set a new password."""
    password = _read_password(password_stdin)

    def run(conn: Connection) -> str:
        u = accounts.require_user(conn, username)
        accounts.set_password(conn, Passwords(), u.id, password, now_ms())
        return f"password changed for {u.username}"

    _transaction(database_url, run)


@user.command("set-name")
@click.argument("username")
@click.argument("name", required=False)
@database_option
def user_set_name(username: str, name: str | None, database_url: str) -> None:
    """Set the display name; without NAME it is cleared (the username is shown)."""

    def run(conn: Connection) -> str:
        u = accounts.require_user(conn, username)
        stored = accounts.set_display_name(conn, u.id, name, now_ms())
        return (
            f"{u.username}: display name {stored!r}" if stored else f"{u.username}: no display name"
        )

    _transaction(database_url, run)


@user.command("list")
@database_option
def user_list(database_url: str) -> None:
    """List accounts and their profiles."""

    def run(conn: Connection) -> str:
        lines = []
        for u in accounts.list_users(conn):
            granted = ", ".join(sorted(accounts.grants(conn, u.id))) or "-"
            state = " (disabled)" if u.disabled else ""
            name = f" name: {u.display_name}" if u.display_name else ""
            lines.append(f"{u.username:<20} {u.role:<8} profiles: {granted}{state}{name}")
        return "\n".join(lines) or "no users"

    _transaction(database_url, run)


def _set_disabled(username: str, disabled: bool, database_url: str) -> None:
    def run(conn: Connection) -> str:
        u = accounts.require_user(conn, username)
        accounts.set_disabled(conn, u.id, disabled, now_ms())
        return f"{'disabled' if disabled else 'enabled'} {u.username}"

    _transaction(database_url, run)


@user.command("disable")
@click.argument("username")
@database_option
def user_disable(username: str, database_url: str) -> None:
    """Disable an account and sign it out."""
    _set_disabled(username, True, database_url)


@user.command("enable")
@click.argument("username")
@database_option
def user_enable(username: str, database_url: str) -> None:
    """Enable a disabled account."""
    _set_disabled(username, False, database_url)


def _change_grants(username: str, profiles: tuple[str, ...], add: bool, database_url: str) -> None:
    def run(conn: Connection) -> str:
        u = accounts.require_user(conn, username)
        current = accounts.grants(conn, u.id)
        wanted = current | set(profiles) if add else current - set(profiles)
        accounts.set_grants(conn, u.id, wanted, now_ms())
        return f"{u.username}: {', '.join(sorted(wanted)) or 'no profiles'}"

    _transaction(database_url, run)


profile_ids_argument = click.argument("profiles", nargs=-1, required=True, metavar="PROFILE_ID...")


@user.command("grant")
@click.argument("username")
@profile_ids_argument
@database_option
def user_grant(username: str, profiles: tuple[str, ...], database_url: str) -> None:
    """Release profiles to an account."""
    _change_grants(username, profiles, True, database_url)


@user.command("revoke")
@click.argument("username")
@profile_ids_argument
@database_option
def user_revoke(username: str, profiles: tuple[str, ...], database_url: str) -> None:
    """Withdraw profiles from an account."""
    _change_grants(username, profiles, False, database_url)


def main(argv: Sequence[str] | None = None) -> int:
    """Run the CLI and return the exit status (also used by tests)."""
    try:
        # Without standalone mode, Click returns the code of click.exceptions.Exit.
        result = cli.main(args=argv, prog_name="capsa", standalone_mode=False)
    except click.ClickException as exc:
        exc.show()
        return exc.exit_code
    except click.Abort:
        err("Aborted!")
        return 1
    return result if isinstance(result, int) else 0


if __name__ == "__main__":
    sys.exit(main())
