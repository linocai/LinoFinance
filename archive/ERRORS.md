## [ERR-20260516-001] pip_editable_install

**Logged**: 2026-05-16T14:31:00+08:00
**Priority**: medium
**Status**: pending
**Area**: backend

### Summary
Editable install failed because the freshly created venv used an old pip that does not support PEP 660 editable installs from `pyproject.toml`.

### Error
```text
ERROR: File "setup.py" or "setup.cfg" not found. Directory cannot be installed in editable mode
```

### Context
- Command: `pip install -e ".[dev]"`
- Project: `backend/pyproject.toml`
- Environment: macOS Python 3.9 venv with pip 21.2.4

### Suggested Fix
Upgrade pip/setuptools/wheel inside the venv before installing backend dependencies.

### Metadata
- Reproducible: yes
- Related Files: backend/README.md, backend/pyproject.toml

---

## [ERR-20260516-004] decimal_scale_api_response

**Logged**: 2026-05-16T14:36:00+08:00
**Priority**: low
**Status**: pending
**Area**: backend

### Summary
Currency rate tests showed that SQLAlchemy `Numeric(18, 8)` preserves database scale in API output, returning `6.80000000` instead of the product-confirmed display value `6.8`.

### Error
```text
AssertionError: assert '6.80000000' == '6.8'
```

### Context
- Command: `pytest`
- Endpoint: `POST /api/v1/currency-rates`

### Suggested Fix
Serialize currency rates with trailing zero trimming at the API schema layer while keeping database precision.

### Metadata
- Reproducible: yes
- Related Files: backend/app/schemas/currency_rate.py

---

## [ERR-20260516-003] sqlAlchemy_date_annotation_shadowing

**Logged**: 2026-05-16T14:33:00+08:00
**Priority**: medium
**Status**: pending
**Area**: backend

### Summary
Alembic import failed because a SQLAlchemy mapped class used `date: Mapped[date]` under Python 3.9, causing the field name to shadow the imported `date` type during annotation evaluation.

### Error
```text
TypeError: Parameters to generic types must be types. Got <sqlalchemy.orm.properties.MappedColumn object ...>
```

### Context
- Command: `alembic upgrade head --sql`
- Affected files: backend/app/models/currency_rate.py, backend/app/models/entry.py

### Suggested Fix
Alias the imported type with `from datetime import date as DateType` and annotate with `Mapped[DateType]`.

### Metadata
- Reproducible: yes
- Related Files: backend/app/models/currency_rate.py, backend/app/models/entry.py, backend/app/models/credit_statement_cycle.py

---

## [ERR-20260516-002] setuptools_package_discovery

**Logged**: 2026-05-16T14:32:00+08:00
**Priority**: medium
**Status**: pending
**Area**: backend

### Summary
Editable install failed after pip upgrade because setuptools auto-discovered both `app` and `alembic` as top-level packages.

### Error
```text
error: Multiple top-level packages discovered in a flat-layout: ['app', 'alembic'].
```

### Context
- Command: `pip install -e ".[dev]"`
- Project layout: `backend/app` plus `backend/alembic`

### Suggested Fix
Configure setuptools package discovery explicitly with `include = ["app*"]`.

### Metadata
- Reproducible: yes
- Related Files: backend/pyproject.toml

---
