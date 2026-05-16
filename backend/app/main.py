from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.core.middleware import APIAuthMiddleware, RateLimitMiddleware, RequestContextMiddleware


def create_app() -> FastAPI:
    settings = get_settings()
    settings.validate_runtime()
    configure_logging(settings)
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        openapi_url=f"{settings.api_v1_prefix}/openapi.json",
        docs_url=f"{settings.api_v1_prefix}/docs" if settings.public_docs_enabled else None,
        redoc_url=f"{settings.api_v1_prefix}/redoc" if settings.public_docs_enabled else None,
    )
    if settings.cors_allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allowed_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    app.add_middleware(RateLimitMiddleware, settings=settings)
    app.add_middleware(APIAuthMiddleware, settings=settings)
    app.add_middleware(RequestContextMiddleware)
    app.include_router(api_router, prefix=settings.api_v1_prefix)
    return app


app = create_app()
