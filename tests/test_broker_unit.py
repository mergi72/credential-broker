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
    assert response.source is None
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
    assert response.source == "windows"
    assert response.auth is not None
    assert response.auth.mode == "credentials"
    assert response.auth.username == "user@example.com"
    assert response.auth.password == "secret"
    assert response.auth.credential_id == "tc-wfx/bridge"


def test_resolve_logs_main_operation_without_secret(monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture) -> None:
    monkeypatch.setattr(
        broker_module,
        "read_windows_credential",
        lambda target: WindowsCredential(target=target, username="user@example.com", password="secret"),
    )
    request = CredentialRequest.model_validate({"auth": {"mode": "windows", "target": "openai/eli", "required": True}})

    with caplog.at_level("INFO", logger="credential_broker.broker"):
        response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert "credential_resolve_start mode=windows credential_id=openai/eli" in caplog.text
    assert "credential_backend_done backend=windows credential_id=openai/eli status=ok" in caplog.text
    assert "credential_resolve_done mode=windows credential_id=openai/eli ok=True" in caplog.text
    assert "secret" not in caplog.text
    assert "user@example.com" not in caplog.text


def test_required_missing_windows_credential_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    def missing(_target: str):
        raise CredentialNotFoundError("missing")

    monkeypatch.setattr(broker_module, "read_windows_credential", missing)
    request = CredentialRequest.model_validate({"auth": {"mode": "windows", "target": "tc-wfx/bridge", "required": True}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is False
    assert response.source is None
    assert response.auth is None
    assert response.message == "missing"


def test_optional_missing_windows_credential_returns_none_auth(monkeypatch: pytest.MonkeyPatch) -> None:
    def missing(_target: str):
        raise CredentialNotFoundError("missing")

    monkeypatch.setattr(broker_module, "read_windows_credential", missing)
    request = CredentialRequest.model_validate({"auth": {"mode": "windows", "target": "tc-wfx/bridge", "required": False}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert response.source is None
    assert response.auth is not None
    assert response.auth.mode == "none"
    assert response.message == "missing"


def test_unsupported_required_mode_fails() -> None:
    request = CredentialRequest.model_validate({"auth": {"mode": "vault", "required": True}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is False
    assert response.source is None
    assert response.auth is None
    assert response.message == "Unsupported credential mode: vault"


def test_unsupported_optional_mode_returns_none_auth() -> None:
    request = CredentialRequest.model_validate({"auth": {"mode": "vault", "required": False}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert response.source is None
    assert response.auth is not None
    assert response.auth.mode == "none"


def test_resolve_credentials_dispatches_registered_resolver(monkeypatch: pytest.MonkeyPatch) -> None:
    called = []

    def resolver(request: CredentialRequest):
        called.append(request.auth.mode)
        return broker_module.CredentialResponse(ok=True, source="test-store", auth=broker_module.AuthContext(mode="none"))

    monkeypatch.setitem(broker_module._RESOLVERS, "test-store", resolver)
    request = CredentialRequest.model_validate({"auth": {"mode": "test-store", "required": True}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert response.source == "test-store"
    assert called == ["test-store"]


def test_resolve_windows_token_credential_returns_token_auth(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        broker_module,
        "read_windows_credential",
        lambda target: WindowsCredential(target=target, username="ignored@example.com", token="token-value"),
    )
    request = CredentialRequest.model_validate({"auth": {"mode": "windows", "target": "tc-wfx/bridge", "required": True}})

    response = broker_module.resolve_credentials(request)

    assert response.ok is True
    assert response.source == "windows"
    assert response.auth is not None
    assert response.auth.mode == "token"
    assert response.auth.token == "token-value"
    assert response.auth.username is None
    assert response.auth.password is None
    assert response.auth.credential_id == "tc-wfx/bridge"
