from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.auth_context import get_auth_context
from app.db.session import get_db
from app.schemas.auth import (
    AppleSignInRequest,
    AppleSignInResponse,
    AuthMeResponse,
    AuthSessionListItem,
    AuthSessionListResponse,
    AuthSessionRead,
    AuthUser,
)
from app.services import auth as auth_service
from app.services.auth import InvalidAppleTokenError, UserDisabledError

router = APIRouter()

_VALID_PLATFORMS = {"ios", "macos"}


@router.post("/apple", response_model=AppleSignInResponse)
def sign_in_with_apple(
    payload: AppleSignInRequest, db: Session = Depends(get_db)
) -> AppleSignInResponse:
    if payload.platform not in _VALID_PLATFORMS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="platform must be one of: ios, macos",
        )

    try:
        user, session, plaintext = auth_service.sign_in_with_apple(
            db,
            identity_token=payload.identity_token,
            device_label=payload.device_label,
            platform=payload.platform,
            app_version=payload.app_version,
            first_name=payload.first_name,
            last_name=payload.last_name,
        )
    except InvalidAppleTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid Apple identity token: {exc}",
        ) from exc
    except UserDisabledError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User is disabled",
        ) from exc

    return AppleSignInResponse(
        session_token=plaintext,
        expires_at=session.expires_at,
        user=AuthUser.model_validate(user),
    )


@router.get("/me", response_model=AuthMeResponse)
def read_me(request: Request) -> AuthMeResponse:
    auth = get_auth_context(request)
    if auth is None or auth.mode == "admin":
        return AuthMeResponse(user=None, session=None, admin=True)
    return AuthMeResponse(
        user=AuthUser.model_validate(auth.user),
        session=AuthSessionRead.model_validate(auth.session),
        admin=False,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(request: Request, db: Session = Depends(get_db)) -> None:
    auth = get_auth_context(request)
    if auth is None or auth.mode == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin token cannot log out",
        )
    # auth.session is detached from the middleware DB session; revoke by id on
    # this route's own session so the change is persisted.
    auth_service.revoke_session_by_id(db, auth.user.id, auth.session.id)


@router.get("/sessions", response_model=AuthSessionListResponse)
def list_sessions(request: Request, db: Session = Depends(get_db)) -> AuthSessionListResponse:
    auth = get_auth_context(request)
    if auth is None or auth.mode == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin token cannot list sessions",
        )
    current_id = auth.session.id
    sessions = auth_service.list_sessions(db, auth.user.id)
    items = [
        AuthSessionListItem(
            id=s.id,
            device_label=s.device_label,
            platform=s.platform,
            app_version=s.app_version,
            issued_at=s.issued_at,
            last_seen_at=s.last_seen_at,
            expires_at=s.expires_at,
            is_current=(s.id == current_id),
        )
        for s in sessions
    ]
    return AuthSessionListResponse(items=items)


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_session(
    session_id: str, request: Request, db: Session = Depends(get_db)
) -> None:
    auth = get_auth_context(request)
    if auth is None or auth.mode == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin token cannot revoke sessions",
        )
    revoked = auth_service.revoke_session_by_id(db, auth.user.id, session_id)
    if not revoked:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found",
        )
