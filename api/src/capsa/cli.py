"""The `capsa` command line tool."""

from __future__ import annotations

import argparse
import csv
import getpass
import json
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

import yaml

from capsa import accounts, migrate
from capsa.accounts import AccountError
from capsa.app import create_app
from capsa.clock import now_ms
from capsa.config import Settings
from capsa.csv_import import CsvImportError, ProfileMeta, rows_to_profile
from capsa.db import make_engine
from capsa.lint import lint_profile
from capsa.passwords import PasswordPolicyError, Passwords
from capsa.profile_io import dump_profile, load_profile
from capsa.validate import Issue, summary, validate_profile


def _check_files(
    paths: Sequence[str], strict: bool, extra: Callable[[Any], list[Issue]] | None = None
) -> int:
    """Validate each profile (and run `extra` checks on valid ones); print a report."""
    failed = False
    for path in paths:
        try:
            data = load_profile(path)
        except (OSError, yaml.YAMLError) as exc:
            print(f"{path}: cannot load: {exc}", file=sys.stderr)
            failed = True
            continue

        issues = validate_profile(data)
        errors = [i for i in issues if i.level == "error"]
        if not errors and extra is not None:
            issues += extra(data)
        warnings = [i for i in issues if i.level == "warning"]
        for issue in issues:
            print(f"{path}: {issue}")
        if errors or (strict and warnings):
            failed = True
            status = "FAILED"
        else:
            status = "ok"
        counts = summary(data) if not errors else {}
        detail = f"{len(counts)} units, {sum(counts.values())} entries, " if counts else ""
        print(f"{path}: {status} ({detail}{len(errors)} errors, {len(warnings)} warnings)")
    return 1 if failed else 0


def cmd_validate(args: argparse.Namespace) -> int:
    return _check_files(args.profiles, args.strict)


def cmd_lint(args: argparse.Namespace) -> int:
    return _check_files(args.profiles, args.strict, extra=lint_profile)


def cmd_import_csv(args: argparse.Namespace) -> int:
    out = Path(args.output)
    if args.output != "-" and out.exists() and not args.force:
        print(f"{out}: exists, use --force to overwrite", file=sys.stderr)
        return 1
    try:
        with open(args.csv, encoding="utf-8-sig", newline="") as f:
            rows = list(csv.reader(f, delimiter=args.delimiter))
    except OSError as exc:
        print(f"{args.csv}: cannot read: {exc}", file=sys.stderr)
        return 1

    meta = ProfileMeta(
        id=args.id, title=args.title, source_lang=args.source_lang, translation_lang=args.tr_lang
    )
    try:
        data = rows_to_profile(rows, meta)
    except CsvImportError as exc:
        for problem in exc.problems:
            print(f"{args.csv}: {problem}", file=sys.stderr)
        return 1

    errors = [i for i in validate_profile(data) if i.level == "error"]
    if errors:
        for issue in errors:
            print(f"{args.csv}: {issue}", file=sys.stderr)
        return 1

    text = dump_profile(data)
    if args.output == "-":
        sys.stdout.write(text)
    else:
        out.write_text(text, encoding="utf-8")
        counts = summary(data)
        print(f"{out}: wrote {len(counts)} units, {sum(counts.values())} entries")
    return 0


def cmd_openapi(args: argparse.Namespace) -> int:
    text = json.dumps(create_app(Settings()).openapi(), indent=2, ensure_ascii=False) + "\n"
    if args.output == "-":
        sys.stdout.write(text)
    else:
        Path(args.output).write_text(text, encoding="utf-8")
    return 0


def cmd_db_upgrade(args: argparse.Namespace) -> int:
    migrate.upgrade(args.database_url)
    print("database is up to date")
    return 0


def _add_database_option(p: argparse.ArgumentParser) -> None:
    p.add_argument(
        "--database-url",
        default=Settings.from_env().database_url,
        help="SQLAlchemy URL (default: $CAPSA_DATABASE_URL or sqlite:///capsa.sqlite)",
    )


def _read_password(args: argparse.Namespace) -> str:
    if args.password_stdin:
        return sys.stdin.readline().rstrip("\r\n")
    first = getpass.getpass("New password: ")
    if getpass.getpass("Repeat password: ") != first:
        raise ValueError("passwords do not match")
    return first


def _user_command(fn: Callable[[Any, argparse.Namespace], str]) -> Callable[..., int]:
    """Run `fn(conn, args)` in a transaction; print its result or the error."""

    def run(args: argparse.Namespace) -> int:
        engine = make_engine(args.database_url)
        try:
            with engine.begin() as conn:
                print(fn(conn, args))
        except (AccountError, PasswordPolicyError, ValueError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        finally:
            engine.dispose()
        return 0

    return run


def _user_add(conn: Any, args: argparse.Namespace) -> str:
    role = "admin" if args.admin else "learner"
    user = accounts.create_user(
        conn, Passwords(), args.username, _read_password(args), role, now_ms()
    )
    return f"created {user.role} {user.username} ({user.id})"


def _user_passwd(conn: Any, args: argparse.Namespace) -> str:
    user = accounts.require_user(conn, args.username)
    accounts.set_password(conn, Passwords(), user.id, _read_password(args), now_ms())
    return f"password changed for {user.username}"


def _user_list(conn: Any, args: argparse.Namespace) -> str:
    lines = []
    for user in accounts.list_users(conn):
        granted = ", ".join(sorted(accounts.grants(conn, user.id))) or "-"
        state = " (disabled)" if user.disabled else ""
        lines.append(f"{user.username:<20} {user.role:<8} profiles: {granted}{state}")
    return "\n".join(lines) or "no users"


def _user_set_disabled(disabled: bool) -> Callable[[Any, argparse.Namespace], str]:
    def run(conn: Any, args: argparse.Namespace) -> str:

        user = accounts.require_user(conn, args.username)
        accounts.set_disabled(conn, user.id, disabled, now_ms())
        return f"{'disabled' if disabled else 'enabled'} {user.username}"

    return run


def _user_grants(add: bool) -> Callable[[Any, argparse.Namespace], str]:
    def run(conn: Any, args: argparse.Namespace) -> str:

        user = accounts.require_user(conn, args.username)
        current = accounts.grants(conn, user.id)
        wanted = current | set(args.profiles) if add else current - set(args.profiles)
        accounts.set_grants(conn, user.id, wanted, now_ms())
        return f"{user.username}: {', '.join(sorted(wanted)) or 'no profiles'}"

    return run


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="capsa", description="Capsa vocabulary trainer tools")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("validate", help="check profiles against the schema and reference rules")
    p.add_argument("profiles", nargs="+", metavar="PROFILE")
    p.add_argument("--strict", action="store_true", help="treat warnings as errors")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("lint", help="validate, then warn about likely mistakes")
    p.add_argument("profiles", nargs="+", metavar="PROFILE")
    p.add_argument("--strict", action="store_true", help="treat warnings as errors")
    p.set_defaults(func=cmd_lint)

    p = sub.add_parser(
        "import-csv", help="create a profile from a CSV file (unit;lemma;info;translation)"
    )
    p.add_argument("csv", metavar="CSV")
    p.add_argument("-o", "--output", required=True, help="profile file to write, '-' for stdout")
    p.add_argument("--id", required=True, help="profile id, e.g. latin-own-words")
    p.add_argument("--title", required=True)
    p.add_argument("--source-lang", required=True, help="language of the lemmas, e.g. la")
    p.add_argument("--tr-lang", required=True, help="language of the translations, e.g. de")
    p.add_argument("--delimiter", default=";", help="column separator (default ';')")
    p.add_argument("--force", action="store_true", help="overwrite an existing output file")
    p.set_defaults(func=cmd_import_csv)

    p = sub.add_parser("openapi", help="write the API description (OpenAPI JSON)")
    p.add_argument("-o", "--output", default="-", help="file to write, '-' for stdout")
    p.set_defaults(func=cmd_openapi)

    db = sub.add_parser("db", help="database maintenance").add_subparsers(
        dest="db_command", required=True
    )
    p = db.add_parser("upgrade", help="apply all pending migrations")
    _add_database_option(p)
    p.set_defaults(func=cmd_db_upgrade)

    user = sub.add_parser("user", help="manage accounts").add_subparsers(
        dest="user_command", required=True
    )
    p = user.add_parser("add", help="create an account (asks for the password)")
    p.add_argument("username")
    p.add_argument("--admin", action="store_true", help="create an admin (parent) account")
    p.add_argument("--password-stdin", action="store_true", help="read the password from stdin")
    p.set_defaults(func=_user_command(_user_add))

    p = user.add_parser("passwd", help="set a new password")
    p.add_argument("username")
    p.add_argument("--password-stdin", action="store_true", help="read the password from stdin")
    p.set_defaults(func=_user_command(_user_passwd))

    p = user.add_parser("list", help="list accounts and their profiles")
    p.set_defaults(func=_user_command(_user_list))

    for name, disabled in (("disable", True), ("enable", False)):
        p = user.add_parser(name, help=f"{name} an account")
        p.add_argument("username")
        p.set_defaults(func=_user_command(_user_set_disabled(disabled)))

    for name, add in (("grant", True), ("revoke", False)):
        verb = "release profiles to" if add else "withdraw profiles from"
        p = user.add_parser(name, help=f"{verb} an account")
        p.add_argument("username")
        p.add_argument("profiles", nargs="+", metavar="PROFILE_ID")
        p.set_defaults(func=_user_command(_user_grants(add)))

    for p in user.choices.values():
        _add_database_option(p)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
