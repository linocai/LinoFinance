from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from app.core.config import get_settings


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a PostgreSQL backup with pg_dump.")
    parser.add_argument("--output-dir", help="Directory for backup artifacts.")
    parser.add_argument("--label", default="manual", help="Short label embedded in the backup name.")
    args = parser.parse_args()

    settings = get_settings()
    output_dir = Path(args.output_dir or settings.backup_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    safe_label = "".join(char if char.isalnum() or char in {"-", "_"} else "-" for char in args.label)
    backup_path = output_dir / f"linofinance-{safe_label}-{timestamp}.dump"

    database_url = _pg_tool_url(settings.database_url)
    subprocess.run(
        [
            "pg_dump",
            "--format=custom",
            "--no-owner",
            "--no-acl",
            "--dbname",
            database_url,
            "--file",
            str(backup_path),
        ],
        check=True,
    )

    manifest = {
        "created_at": timestamp,
        "tool": "pg_dump",
        "format": "custom",
        "backup_file": backup_path.name,
        "sha256": _sha256(backup_path),
        "database_url": _redact_url(database_url),
    }
    manifest_path = backup_path.with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"backup": str(backup_path), "manifest": str(manifest_path)}, indent=2))


def _pg_tool_url(database_url: str) -> str:
    return database_url.replace("postgresql+psycopg://", "postgresql://", 1)


def _redact_url(database_url: str) -> str:
    parsed = urlsplit(database_url)
    if parsed.password is None:
        return database_url
    username = parsed.username or ""
    hostname = parsed.hostname or ""
    port = f":{parsed.port}" if parsed.port else ""
    netloc = f"{username}:***@{hostname}{port}"
    return urlunsplit((parsed.scheme, netloc, parsed.path, parsed.query, parsed.fragment))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    main()
