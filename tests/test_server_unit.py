from __future__ import annotations

import pytest

import credential_broker.server as server_module
from credential_broker.windows_credential_manager import WindowsCredential


pytestmark = pytest.mark.unit


def test_resolve_json_request_returns_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        server_module,
        "read_windows_credential",
        lambda target: WindowsCredential(target=target, username="user@example.com", password="secret"),
        raising=False,
    )
    monkeypatch.setattr(
        "credential_broker.broker.read_windows_credential",
        lambda target: WindowsCredential(target=target, username="user@example.com", password="secret"),
    )

    status, payload = server_module.resolve_json_request(
        b'{"auth":{"mode":"windows","target":"tc-wfx/bridge","required":true}}'
    )

    assert status == 200
    assert payload["ok"] is True
    assert payload["auth"]["mode"] == "credentials"
    assert payload["auth"]["username"] == "user@example.com"
    assert payload["auth"]["password"] == "secret"
    assert payload["auth"]["credential_id"] == "tc-wfx/bridge"


def test_resolve_json_request_rejects_invalid_payload() -> None:
    status, payload = server_module.resolve_json_request(b'{"auth":{}}')

    assert status == 400
    assert payload["ok"] is False
    assert payload["message"] == "Invalid credential request."
    assert payload["errors"]

def test_json_response_serializes_bytes_in_error_payload() -> None:
    status, body = server_module._json_response(400, {"ok": False, "errors": [{"input": b"raw"}]})

    assert status == 400
    assert b'"input": "raw"' in body

def test_resolve_json_request_accepts_pascal_case_payload(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "credential_broker.broker.read_windows_credential",
        lambda target: WindowsCredential(target=target, username="user@example.com", password="secret"),
    )

    status, payload = server_module.resolve_json_request(
        b'{"Provider":"alfresco","Auth":{"Mode":"windows","Target":"tc-wfx/bridge","Required":true}}'
    )

    assert status == 200
    assert payload["ok"] is True
    assert payload["auth"]["username"] == "user@example.com"

