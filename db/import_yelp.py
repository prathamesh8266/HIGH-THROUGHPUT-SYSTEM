#!/usr/bin/env python3
"""Stream a Yelp CSV into an existing, empty table in a Docker container."""

import argparse
import csv
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


CSV_HEADER = (
    "ID", "Time_GMT", "Phone", "Organization", "OLF", "Rating",
    "NumberReview", "Category", "Country", "CountryCode", "State",
    "City", "Street", "Building",
)
DB_COLUMNS = (
    "id", "time_gmt", "phone", "organization", "olf", "rating",
    "number_review", "category", "country", "country_code", "state",
    "city", "street", "building",
)


def inspect_csv(path: Path) -> int:
    """Validate CSV structure and count records without keeping them in memory."""
    with path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.reader(source, strict=True)
        if tuple(next(reader, ())) != CSV_HEADER:
            raise ValueError("CSV header must match the 14 Yelp columns in their original order.")
        row_count = 0
        for row in reader:
            if len(row) != len(CSV_HEADER):
                raise ValueError(
                    f"CSV record ending at line {reader.line_num} has {len(row)} columns; expected 14."
                )
            row_count += 1
    if row_count == 0:
        raise ValueError("CSV contains no data records.")
    return row_count


def import_command(podname: str, database: str, user: str, row_count: int) -> list[str]:
    # The lock prevents two imports or another writer from racing the empty-table check.
    # Regular SELECT requests remain possible. Fail promptly if another writer holds it.
    guard = """
        SET LOCAL lock_timeout = '5s';
        LOCK TABLE public.yelp_businesses IN SHARE ROW EXCLUSIVE MODE;
        DO $import$
        BEGIN
            IF EXISTS (SELECT 1 FROM public.yelp_businesses LIMIT 1) THEN
                RAISE EXCEPTION 'public.yelp_businesses already contains data; import cancelled';
            END IF;
        END;
        $import$;
    """
    copy = (
        f"COPY public.yelp_businesses ({', '.join(DB_COLUMNS)}) "
        "FROM STDIN WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');"
    )
    # Check before commit, including when an interrupted stream ends at a valid row.
    verify = f"""
        DO $import$
        DECLARE
            imported_rows bigint;
            sequence_name text;
            highest_id bigint;
            sequence_value bigint;
            sequence_called boolean;
        BEGIN
            SELECT count(*) INTO imported_rows FROM public.yelp_businesses;
            IF imported_rows <> {row_count} THEN
                RAISE EXCEPTION 'Expected % imported rows, found %', {row_count}, imported_rows;
            END IF;
            -- Explicit CSV IDs do not advance a default sequence. If one exists,
            -- move it forward so later application inserts cannot reuse CSV IDs.
            sequence_name := pg_get_serial_sequence('public.yelp_businesses', 'id');
            IF sequence_name IS NOT NULL THEN
                SELECT max(id) INTO highest_id FROM public.yelp_businesses;
                EXECUTE format('SELECT last_value, is_called FROM %s', sequence_name::regclass)
                    INTO sequence_value, sequence_called;
                PERFORM setval(
                    sequence_name::regclass,
                    greatest(coalesce(highest_id, 1), sequence_value),
                    sequence_called OR highest_id IS NOT NULL
                );
            END IF;
        END;
        $import$;
        SELECT count(*) AS total_rows, min(id) AS first_id, max(id) AS last_id
        FROM public.yelp_businesses;
    """
    return [
        "docker", "exec", "-i", podname,
        "psql", "--no-psqlrc", "--no-password", "--username", user,
        "--dbname", database, "--set=ON_ERROR_STOP=1", "--single-transaction",
        "-c", guard, "-c", copy, "-c", verify,
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Import a Yelp CSV into public.yelp_businesses in a Docker PostgreSQL container. "
        "The table must already exist and be empty."
    )
    parser.add_argument(
        "--podname", "--container", required=True,
        help="Docker PostgreSQL container name or ID (not the application container).",
    )
    parser.add_argument(
        "--csv", type=Path, default=Path(__file__).resolve().with_name("yelp_database.csv"),
        help="CSV path; defaults to yelp_database.csv beside this script.",
    )
    parser.add_argument("--database", default="app", help="Database name (default: app).")
    parser.add_argument("--user", default="app", help="PostgreSQL user (default: app).")
    args = parser.parse_args(argv)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.podname):
        parser.error("--podname must be a Docker container name or ID.")
    if shutil.which("docker") is None:
        parser.error("Docker CLI is unavailable. Run this script from your Docker-enabled WSL terminal.")

    try:
        print(f"Checking {args.csv}...", flush=True)
        row_count = inspect_csv(args.csv)
        print(
            f"Importing {row_count:,} records into {args.podname}/{args.database}:public.yelp_businesses...",
            flush=True,
        )
        started = time.monotonic()
        with args.csv.open("rb") as source:
            result = subprocess.run(
                import_command(args.podname, args.database, args.user, row_count),
                stdin=source,
                check=False,
            )
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        print(f"Import failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Import interrupted; check the target container before retrying.", file=sys.stderr)
        return 130

    if result.returncode:
        print("Import failed; see the Docker/psql error above.", file=sys.stderr)
        return result.returncode
    print(f"Imported {row_count:,} records successfully in {time.monotonic() - started:.1f}s.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
