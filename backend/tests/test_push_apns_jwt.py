"""APNs JWT signing happy-path (v1.2 P7).

The dispatch tests run in dry-run mode and never exercise the real ES256
signing. This test mints a fixture P-256 .p8 and asserts `_apns_jwt`
produces a well-formed, verifiable ES256 provider token.
"""

from __future__ import annotations

import base64
import json
from types import SimpleNamespace

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

from app.services import push_dispatch


def _b64url_decode(segment: str) -> bytes:
    padding = "=" * (-len(segment) % 4)
    return base64.urlsafe_b64decode(segment + padding)


def test_apns_jwt_signs_and_verifies(tmp_path) -> None:
    private_key = ec.generate_private_key(ec.SECP256R1())
    pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    key_path = tmp_path / "AuthKey_TEST123456.p8"
    key_path.write_bytes(pem)

    settings = SimpleNamespace(
        apns_key_id="TEST123456",
        apns_team_id="HX73DFL88G",
        apns_topic="com.lino.linofinance.ios",
        apns_key_path=str(key_path),
    )

    token = push_dispatch._apns_jwt(settings)

    header_b64, claims_b64, signature_b64 = token.split(".")
    header = json.loads(_b64url_decode(header_b64))
    claims = json.loads(_b64url_decode(claims_b64))
    assert header == {"alg": "ES256", "kid": "TEST123456"}
    assert claims["iss"] == "HX73DFL88G"
    assert isinstance(claims["iat"], int)

    # Reconstruct the DER signature from the raw r||s and verify it.
    raw_sig = _b64url_decode(signature_b64)
    assert len(raw_sig) == 64
    r_value = int.from_bytes(raw_sig[:32], "big")
    s_value = int.from_bytes(raw_sig[32:], "big")
    der_sig = utils.encode_dss_signature(r_value, s_value)
    signing_input = f"{header_b64}.{claims_b64}".encode()
    # Raises InvalidSignature if the token was not signed by this key.
    private_key.public_key().verify(der_sig, signing_input, ec.ECDSA(hashes.SHA256()))
