.PHONY: backend-dev backend-migrate backend-test backend-compile backend-backup backend-prod-migrate frontend-test postgres-up status

backend-dev:
	cd backend && uvicorn app.main:app --reload

backend-migrate:
	cd backend && alembic upgrade head

backend-test:
	cd backend && pytest

backend-compile:
	python3 -m compileall backend/app backend/tests

backend-backup:
	cd backend && python scripts/backup_postgres.py --label manual

backend-prod-migrate:
	cd backend && python scripts/production_migrate.py

frontend-test:
	cd frontend && swift test

postgres-up:
	docker compose up -d postgres

status:
	git status --short --branch
