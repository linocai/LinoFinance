"""Tests for the Apple identity_token verification service (P2)."""

from __future__ import annotations

import time

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from jose import jwk, jwt

from app.services import apple_identity
from app.services.apple_identity import AppleIdentityError, verify_apple_identity_token

_TEST_KID = "test-kid"


def _make_fixture_key():
    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pub_jwk = jwk.construct(priv.public_key(), algorithm="RS256").to_dict()
    pub_jwk["kid"] = _TEST_KID
    pub_jwk["use"] = "sig"
    # jose returns n/e as bytes; serialise to str for a JWKS-shaped dict.
    for field in ("n", "e"):
        if isinstance(pub_jwk[field], bytes):
            pub_jwk[field] = pub_jwk[field].decode("ascii")
    return priv, pub_jwk


def _sign(priv, claims, kid=_TEST_KID):
    pem = priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    return jwt.encode(claims, pem, algorithm="RS256", headers={"kid": kid})


def _base_claims(**overrides):
    now = int(time.time())
    claims = {
        "iss": apple_identity.APPLE_ISSUER,
        "aud": "com.lino.linofinance.ios",
        "sub": "test-sub",
        "iat": now,
        "exp": now + 600,
        "email": "abc@example.com",
        "email_verified": "true",
    }
    claims.update(overrides)
    return claims


@pytest.fixture(autouse=True)
def _patch_jwks(monkeypatch):
    priv, pub_jwk = _make_fixture_key()
    monkeypatch.setattr(apple_identity, "_fetch_jwks", lambda: {"keys": [pub_jwk]})
    # Reset module cache between tests for isolation.
    apple_identity._jwks_cache = None
    apple_identity._jwks_cache_expires_at = 0.0
    return priv


def test_verify_rejects_garbage(_patch_jwks):
    with pytest.raises(AppleIdentityError):
        verify_apple_identity_token("not.a.jwt", {"com.lino.linofinance.ios"})


def test_verify_rejects_wrong_audience(_patch_jwks):
    priv = _patch_jwks
    token = _sign(priv, _base_claims())
    with pytest.raises(AppleIdentityError):
        verify_apple_identity_token(token, {"com.example.other"})


def test_verify_accepts_valid_token(_patch_jwks):
    priv = _patch_jwks
    token = _sign(priv, _base_claims())
    result = verify_apple_identity_token(token, {"com.lino.linofinance.ios"})
    assert result.sub == "test-sub"
    assert result.email == "abc@example.com"
    assert result.email_verified is True
    assert result.aud == "com.lino.linofinance.ios"
    assert result.is_private_email is False


def test_verify_extracts_private_email_flag(_patch_jwks):
    priv = _patch_jwks
    token = _sign(priv, _base_claims(email="abc@privaterelay.appleid.com"))
    result = verify_apple_identity_token(token, {"com.lino.linofinance.ios"})
    assert result.is_private_email is True
