from __future__ import annotations

import pytest

import credential_broker.broker as broker_module
from credential_broker.models import CredentialRequest
from credential_broker.windows_credential_manager import CredentialNotFoundError, WindowsCredential


pytestmark = pytest.mark.unit


def test_resolve_none_mode() -> None:
    request = CredentialRequest.model_validate({"auth": {"mode": "none", "required": False}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert response.auth is not None
    assert response.auth.mode == "none"


def test_resolve_windows_credential(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        broker_module,
        "read_windows_credential",
        lambda target: WindowsCredential(target=target, username="user@example.com", password="secret"),
    )
    request = CredentialRequest.model_validate({"auth": {"mode": "windows", "target": "tc-wfx/bridge", "required": True}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert response.auth is not None
    assert response.auth.mode == "credentials"
    assert response.auth.username == "user@example.com"
    assert response.auth.password == "secret"
    assert response.auth.credential_id == "tc-wfx/bridge"


def test_required_missing_windows_credential_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    def missing(_target: str):
        raise CredentialNotFoundError("missing")

    monkeypatch.setattr(broker_module, "read_windows_credential", missing)
    request = CredentialRequest.model_validate({"auth": {"mode": "windows", "target": "tc-wfx/bridge", "required": True}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is False
    assert response.auth is None
    assert response.message == "missing"


def test_optional_missing_windows_credential_returns_none_auth(monkeypatch: pytest.MonkeyPatch) -> None:
    def missing(_target: str):
        raise CredentialNotFoundError("missing")

    monkeypatch.setattr(broker_module, "read_windows_credential", missing)
    request = CredentialRequest.model_validate({"auth": {"mode": "windows", "target": "tc-wfx/bridge", "required": False}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert response.auth is not None
    assert response.auth.mode == "none"
    assert response.message == "missing"
