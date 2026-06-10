"""P7 protection + export closure (audit 2.1 / 2.4 / 2.7)."""

from app.core.middleware import _InMemoryRateLimiter


# --------------------------------------------------------------------------
# audit 2.1 — bounded in-memory rate limiter (decision D5)
# --------------------------------------------------------------------------


def test_rate_limiter_sweeps_expired_windows() -> None:
    limiter = _InMemoryRateLimiter(limit_per_minute=100)

    # Seed three windows at t=0.
    for key in ("a", "b", "c"):
        limiter.hit(key, now=0.0)
    assert len(limiter._windows) == 3

    # A hit > 60s later triggers a full sweep of the now-expired windows; only
    # the freshly created window for "d" should remain.
    limiter.hit("d", now=120.0)
    assert set(limiter._windows.keys()) == {"d"}


def test_rate_limiter_evicts_oldest_when_at_capacity() -> None:
    limiter = _InMemoryRateLimiter(limit_per_minute=100)
    limiter.MAX_KEYS = 3  # shrink the cap for the test

    # Fill to capacity with staggered start times within the same window so the
    # periodic sweep does not drop any of them.
    limiter.hit("oldest", now=1000.0)
    limiter.hit("mid", now=1000.5)
    limiter.hit("newest", now=1001.0)
    assert len(limiter._windows) == 3

    # A fourth distinct key at capacity (still inside the 60s window so nothing
    # is sweepable) evicts the window with the oldest started_at.
    limiter.hit("fourth", now=1001.5)
    assert len(limiter._windows) == 3
    assert "oldest" not in limiter._windows
    assert {"mid", "newest", "fourth"}.issubset(limiter._windows.keys())


def test_rate_limiter_enforces_limit_within_window() -> None:
    limiter = _InMemoryRateLimiter(limit_per_minute=2)
    assert limiter.hit("k", now=0.0)[0] is True
    assert limiter.hit("k", now=0.1)[0] is True
    allowed, _, remaining = limiter.hit("k", now=0.2)
    assert allowed is False
    assert remaining == 0
    # A new window after 60s resets the counter.
    assert limiter.hit("k", now=61.0)[0] is True


# --------------------------------------------------------------------------
# audit 2.4 — attachment owner existence
# --------------------------------------------------------------------------


def _make_entry_line(client) -> str:
    account = client.post(
        "/api/v1/accounts",
        json={"name": "W", "type": "balance", "currency": "CNY", "current_balance": "100"},
    ).json()
    category = client.post(
        "/api/v1/categories", json={"name": "C", "type": "expense"}
    ).json()
    entry = client.post(
        "/api/v1/entries",
        json={
            "title": "E",
            "date": "2026-05-20",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "10",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "10",
                    "currency": "CNY",
                }
            ],
        },
    ).json()
    return entry["category_lines"][0]["id"]


def test_attachment_upload_unknown_owner_returns_404(client, monkeypatch, tmp_path) -> None:
    from app.core.config import get_settings

    monkeypatch.setenv("LINOFINANCE_STORAGE_ROOT", str(tmp_path))
    get_settings.cache_clear()

    response = client.post(
        "/api/v1/attachments",
        data={"owner_type": "entry_category_line", "owner_id": "ghost-line"},
        files={"file": ("x.txt", b"data", "text/plain")},
    )
    assert response.status_code == 404
    get_settings.cache_clear()


def test_attachment_upload_real_owner_succeeds(client, monkeypatch, tmp_path) -> None:
    from app.core.config import get_settings

    monkeypatch.setenv("LINOFINANCE_STORAGE_ROOT", str(tmp_path))
    get_settings.cache_clear()

    line_id = _make_entry_line(client)
    response = client.post(
        "/api/v1/attachments",
        data={"owner_type": "entry_category_line", "owner_id": line_id},
        files={"file": ("x.txt", b"data", "text/plain")},
    )
    assert response.status_code == 201
    assert response.json()["owner_id"] == line_id
    get_settings.cache_clear()


# --------------------------------------------------------------------------
# audit 2.7 — export dataset closure
# --------------------------------------------------------------------------


def test_new_export_datasets_listed_and_exportable(client) -> None:
    # Seed referenceable master data so the rows are non-empty where possible.
    client.post(
        "/api/v1/categories", json={"name": "Travel", "type": "expense"}
    )
    client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": "6.8",
            "date": "2026-05-16",
            "source": "manual",
        },
    )

    datasets = client.get("/api/v1/exports/csv")
    assert datasets.status_code == 200
    names = {d["name"] for d in datasets.json()["datasets"]}
    assert {
        "categories",
        "currency_rates",
        "account_adjustments",
        "attachments",
    }.issubset(names)

    categories_csv = client.get("/api/v1/exports/csv/categories")
    assert categories_csv.status_code == 200
    assert categories_csv.headers["content-type"].startswith("text/csv")
    assert "name,parent_id,type,is_active,display_order" in categories_csv.text
    assert "Travel" in categories_csv.text

    rates_csv = client.get("/api/v1/exports/csv/currency_rates")
    assert rates_csv.status_code == 200
    assert "from_currency,to_currency,rate,date" in rates_csv.text
    assert "USD,CNY,6.8" in rates_csv.text

    # account_adjustments + attachments export their header even when empty.
    for dataset in ("account_adjustments", "attachments"):
        resp = client.get(f"/api/v1/exports/csv/{dataset}")
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("text/csv")


def test_unknown_export_dataset_still_400(client) -> None:
    assert client.get("/api/v1/exports/csv/bogus").status_code == 400
