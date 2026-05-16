.PHONY: backend-dev backend-migrate backend-test backend-compile frontend-test status

backend-dev:
	cd backend && uvicorn app.main:app --reload

backend-migrate:
	cd backend && alembic upgrade head

backend-test:
	cd backend && pytest

backend-compile:
	python3 -m compileall backend/app backend/tests

frontend-test:
	cd frontend && swift test

status:
	git status --short --branch

