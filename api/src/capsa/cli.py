"""The `capsa` command line tool."""

from __future__ import annotations

import argparse
import csv
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

import yaml

from capsa.csv_import import CsvImportError, ProfileMeta, rows_to_profile
from capsa.lint import lint_profile
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
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
