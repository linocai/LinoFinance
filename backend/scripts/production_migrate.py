from __future__ import annotations

import argparse
import subprocess
import sys

from app.core.config import get_settings


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a production migration flow.")
    parser.add_argument(
        "--skip-backup",
        action="store_true",
        help="Run Alembic without taking a pre-migration backup.",
    )
    args = parser.parse_args()

    settings = get_settings()
    settings.validate_runtime()

    # Use sys.executable so the same venv's Python (and its installed
    # `alembic` / dependencies) is reused for the child processes. The host
    # may only ship `python3`, not `python`, so a bare "python" call fails.
    python = sys.executable

    if not args.skip_backup:
        subprocess.run(
            [python, "scripts/backup_postgres.py", "--label", "pre-migration"],
            check=True,
        )

    subprocess.run([python, "-m", "alembic", "upgrade", "head"], check=True)


if __name__ == "__main__":
    main()
