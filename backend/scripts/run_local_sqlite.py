from datetime import date
from decimal import Decimal
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCAL_DIR = ROOT / ".local"
DB_PATH = LOCAL_DIR / "linofinance.sqlite3"

os.environ["LINOFINANCE_DATABASE_URL"] = f"sqlite+pysqlite:///{DB_PATH}"
os.environ["LINOFINANCE_API_HOST"] = "127.0.0.1"
os.environ["LINOFINANCE_API_PORT"] = "6868"

LOCAL_DIR.mkdir(parents=True, exist_ok=True)

from app import models  # noqa: E402,F401
from app.db.base import Base  # noqa: E402
from app.db.session import engine, SessionLocal  # noqa: E402
from app.models.currency_rate import CurrencyRate  # noqa: E402


def bootstrap_database() -> None:
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        existing = db.get(CurrencyRate, "00000000-0000-0000-0000-000000000680")
        if existing is None:
            db.add(
                CurrencyRate(
                    id="00000000-0000-0000-0000-000000000680",
                    from_currency="USD",
                    to_currency="CNY",
                    rate=Decimal("6.8"),
                    date=date(2026, 5, 16),
                    source="manual",
                    note="Initial manual USD/CNY rate confirmed for local testing.",
                )
            )
            db.commit()


if __name__ == "__main__":
    import uvicorn

    bootstrap_database()
    uvicorn.run(
        "app.main:app",
        host="127.0.0.1",
        port=6868,
        reload=False,
    )
