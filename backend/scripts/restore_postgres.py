from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from app.core.config import get_settings


def main() -> None:
    parser = argparse.ArgumentParser(description="Restore a PostgreSQL custom-format backup.")
    parser.add_argument("backup", help="Path to a .dump file created by backup_postgres.py.")
    parser.add_argument(
        "--confirm",
        choices=["RESTORE_LINOFINANCE"],
        help="Required destructive confirmation.",
    )
    args = parser.parse_args()

    if args.confirm != "RESTORE_LINOFINANCE":
        raise SystemExit("Refusing to restore without --confirm RESTORE_LINOFINANCE")

    backup_path = Path(args.backup)
    if not backup_path.exists():
        raise SystemExit(f"Backup file not found: {backup_path}")

    settings = get_settings()
    subprocess.run(
        [
            "pg_restore",
            "--clean",
            "--if-exists",
            "--no-owner",
            "--no-acl",
            "--dbname",
            _pg_tool_url(settings.database_url),
            str(backup_path),
        ],
        check=True,
    )


def _pg_tool_url(database_url: str) -> str:
    return database_url.replace("postgresql+psycopg://", "postgresql://", 1)


if __name__ == "__main__":
    main()
