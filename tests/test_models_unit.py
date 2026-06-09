from __future__ import annotations

import pytest
from pydantic import ValidationError

from credential_broker.models import AuthContext, CredentialRequest


pytestmark = pytest.mark.unit


def test_auth_requirement_accepts_target_base_alias() -> None:
    request = CredentialRequest.model_validate(
        {
            "auth": {
                "mode": "windows",
                "targetBase": "example/base",
                "required": True,
            },
        }
    )

    assert request.auth.target_base == "example/base"


@pytest.mark.parametrize("field", ["provider", "user"])
def test_credential_request_rejects_unused_fields(field: str) -> None:
    with pytest.raises(ValidationError):
        CredentialRequest.model_validate(
            {
                field: {},
                "auth": {
                    "mode": "windows",
                    "target": "tc-wfx/bridge",
                    "required": True,
                },
            }
        )


def test_auth_context_rejects_credentials_with_token() -> None:
    with pytest.raises(ValidationError):
        AuthContext(mode="credentials", username="user", password="secret", token="token")


def test_auth_context_rejects_token_with_password() -> None:
    with pytest.raises(ValidationError):
        AuthContext(mode="token", username="user", password="secret", token="token")


def test_auth_context_accepts_token_only() -> None:
    auth = AuthContext(mode="token", token="token", credential_id="target")

    assert auth.mode == "token"
    assert auth.token == "token"
    assert auth.username is None
    assert auth.password is None


def test_auth_context_accepts_credentials_without_token() -> None:
    auth = AuthContext(mode="credentials", username="user", password="secret", credential_id="target")

    assert auth.mode == "credentials"
    assert auth.username == "user"
    assert auth.password == "secret"
    assert auth.token is None
