"""Apple Sign in with Apple identity_token verification.

Pure verification layer: takes Apple's identity_token JWT, validates the
signature against Apple's published JWKS plus the standard issuer/audience/
expiry claims, and returns the validated identity. No DB access here.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Optional

import httpx
from jose import jwt

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"

_jwks_cache: Optional[dict] = None
_jwks_cache_expires_at: float = 0.0
_JWKS_TTL_SECONDS = 3600


@dataclass(frozen=True)
class AppleIdentity:
    sub: str  # Apple's stable user id
    email: Optional[str]
    email_verified: bool
    aud: str  # bundle id, e.g. com.lino.linofinance.ios
    iss: str
    iat: int
    exp: int
    is_private_email: bool  # email ends with @privaterelay.appleid.com


class AppleIdentityError(Exception):
    pass


def _fetch_jwks() -> dict:
    global _jwks_cache, _jwks_cache_expires_at
    now = time.time()
    if _jwks_cache is not None and now < _jwks_cache_expires_at:
        return _jwks_cache
    response = httpx.get(APPLE_JWKS_URL, timeout=10.0)
    response.raise_for_status()
    _jwks_cache = response.json()
    _jwks_cache_expires_at = now + _JWKS_TTL_SECONDS
    return _jwks_cache


def verify_apple_identity_token(
    token: str,
    expected_audiences: set,
) -> AppleIdentity:
    """Verify an Apple identity_token against Apple's JWKS.

    `expected_audiences` is the set of bundle IDs the server will accept.
    For LinoFinance v1.2 this is exactly
    {"com.lino.linofinance.ios", "com.lino.linofinance"}.
    """
    try:
        unverified_header = jwt.get_unverified_header(token)
    except Exception as exc:
        raise AppleIdentityError(f"Invalid token header: {exc}") from exc

    kid = unverified_header.get("kid")
    alg = unverified_header.get("alg")
    if not kid or alg != "RS256":
        raise AppleIdentityError("Unsupported token header (kid/alg)")

    jwks = _fetch_jwks()
    key = next((k for k in jwks["keys"] if k["kid"] == kid), None)
    if key is None:
        # Cache may be stale — bust once and refetch.
        global _jwks_cache_expires_at
        _jwks_cache_expires_at = 0.0
        jwks = _fetch_jwks()
        key = next((k for k in jwks["keys"] if k["kid"] == kid), None)
    if key is None:
        raise AppleIdentityError("Token kid not in Apple JWKS")

    # python-jose only accepts a single-string audience, while Apple may be
    # accessed from several bundle IDs. Verify the signature / issuer / expiry
    # via jose with the audience check disabled, then match `aud` against the
    # accepted set ourselves.
    try:
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            issuer=APPLE_ISSUER,
            options={"verify_aud": False},
        )
    except Exception as exc:
        raise AppleIdentityError(f"JWT verification failed: {exc}") from exc

    aud = claims.get("aud")
    if aud not in expected_audiences:
        raise AppleIdentityError(f"Token audience '{aud}' not accepted")

    sub = claims.get("sub")
    if not sub:
        raise AppleIdentityError("Token has no sub claim")

    email = claims.get("email")
    return AppleIdentity(
        sub=sub,
        email=email,
        email_verified=str(claims.get("email_verified", "false")).lower() == "true",
        aud=claims["aud"],
        iss=claims["iss"],
        iat=int(claims["iat"]),
        exp=int(claims["exp"]),
        is_private_email=bool(email and email.endswith("@privaterelay.appleid.com")),
    )
