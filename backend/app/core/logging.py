import logging

from app.core.config import Settings


def configure_logging(settings: Settings) -> None:
    logging.basicConfig(
        level=settings.log_level.upper(),
        format="%(message)s",
        force=True,
    )
