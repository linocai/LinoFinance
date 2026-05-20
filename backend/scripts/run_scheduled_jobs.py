from __future__ import annotations

import argparse

from app import models  # noqa: F401
from app.db.session import SessionLocal
from app.services import attachments, push_dispatch


def main() -> None:
    parser = argparse.ArgumentParser(description="Run LinoFinance scheduled jobs once.")
    parser.add_argument("--skip-push", action="store_true", help="Skip APNs reminder dispatch.")
    parser.add_argument("--skip-cleanup", action="store_true", help="Skip attachment cleanup.")
    parser.add_argument(
        "--attachment-retention-days",
        type=int,
        default=30,
        help="Days to retain soft-deleted attachment files.",
    )
    args = parser.parse_args()

    with SessionLocal() as db:
        if not args.skip_push:
            push_dispatch.dispatch_due_credit_reminders(db)
        if not args.skip_cleanup:
            attachments.cleanup_deleted_attachments(
                db,
                retention_days=args.attachment_retention_days,
            )


if __name__ == "__main__":
    main()
