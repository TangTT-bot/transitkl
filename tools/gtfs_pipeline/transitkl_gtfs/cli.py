from __future__ import annotations

import argparse
from pathlib import Path
from urllib.error import URLError

from .audit import AuditReport, audit_feed
from .database import FeedValidationError, build_database
from .download import download_feed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="transitkl-gtfs",
        description="Audit GTFS Schedule feeds and build TransitKL SQLite databases.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    download_parser = subparsers.add_parser("download", help="Download a GTFS ZIP feed.")
    download_parser.add_argument("--url", required=True)
    download_parser.add_argument("--output", required=True, type=Path)
    download_parser.add_argument("--overwrite", action="store_true")

    audit_parser = subparsers.add_parser("audit", help="Validate and report on a GTFS feed.")
    _add_feed_arguments(audit_parser)
    audit_parser.add_argument("--markdown-report", type=Path)
    audit_parser.add_argument("--json-report", type=Path)

    build_parser_command = subparsers.add_parser(
        "build",
        help="Validate a GTFS feed and convert its core tables to SQLite.",
    )
    _add_feed_arguments(build_parser_command)
    build_parser_command.add_argument("--database", required=True, type=Path)
    build_parser_command.add_argument("--markdown-report", type=Path)
    build_parser_command.add_argument("--json-report", type=Path)
    build_parser_command.add_argument(
        "--allow-errors",
        action="store_true",
        help="Build despite audit errors. Intended only for diagnosis.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "download":
            output = download_feed(args.url, args.output, overwrite=args.overwrite)
            print(f"Downloaded GTFS feed to {output}")
            return 0

        if args.command == "audit":
            report = audit_feed(args.input, args.feed_id)
            _write_reports(report, args.markdown_report, args.json_report)
            _print_summary(report)
            return 0 if report.is_valid else 1

        if args.command == "build":
            report = build_database(
                args.input,
                args.feed_id,
                args.database,
                allow_errors=args.allow_errors,
            )
            _write_reports(report, args.markdown_report, args.json_report)
            _print_summary(report)
            print(f"Built SQLite database at {args.database.resolve()}")
            return 0
    except (OSError, URLError, FeedValidationError, ValueError) as error:
        print(f"Error: {error}")
        return 2

    return 2


def _add_feed_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument(
        "--feed-id",
        required=True,
        help="Stable namespace, for example prasarana_rapid_rail.",
    )


def _write_reports(
    report: AuditReport,
    markdown_path: Path | None,
    json_path: Path | None,
) -> None:
    if markdown_path:
        report.write_markdown(markdown_path)
        print(f"Wrote Markdown audit to {markdown_path.resolve()}")
    if json_path:
        report.write_json(json_path)
        print(f"Wrote JSON audit to {json_path.resolve()}")


def _print_summary(report: AuditReport) -> None:
    status = "PASS" if report.is_valid else "FAIL"
    print(
        f"GTFS audit {status}: {report.error_count} error(s), "
        f"{report.warning_count} warning(s), {sum(report.row_counts.values())} total row(s)."
    )
