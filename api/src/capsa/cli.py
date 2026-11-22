"""The `capsa` command line tool."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence

import yaml

from capsa.profile_io import load_profile
from capsa.validate import summary, validate_profile


def cmd_validate(args: argparse.Namespace) -> int:
    failed = False
    for path in args.profiles:
        try:
            data = load_profile(path)
        except (OSError, yaml.YAMLError) as exc:
            print(f"{path}: cannot load: {exc}", file=sys.stderr)
            failed = True
            continue

        issues = validate_profile(data)
        errors = [i for i in issues if i.level == "error"]
        warnings = [i for i in issues if i.level == "warning"]
        for issue in issues:
            print(f"{path}: {issue}")
        if errors or (args.strict and warnings):
            failed = True
            status = "FAILED"
        else:
            status = "ok"
        counts = summary(data) if not errors else {}
        total = sum(counts.values())
        detail = f"{len(counts)} units, {total} entries, " if counts else ""
        print(f"{path}: {status} ({detail}{len(errors)} errors, {len(warnings)} warnings)")
    return 1 if failed else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="capsa", description="Capsa vocabulary trainer tools")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("validate", help="check profiles against the schema and reference rules")
    p.add_argument("profiles", nargs="+", metavar="PROFILE")
    p.add_argument("--strict", action="store_true", help="treat warnings as errors")
    p.set_defaults(func=cmd_validate)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
