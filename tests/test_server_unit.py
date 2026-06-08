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
        b'{"Auth":{"Mode":"windows","Target":"tc-wfx/bridge","Required":true}}'
    )

    assert status == 200
    assert payload["ok"] is True
    assert payload["auth"]["username"] == "user@example.com"



def test_validate_bind_host_allows_loopback_hosts() -> None:
    assert server_module.validate_bind_host("127.0.0.1") == "127.0.0.1"
    assert server_module.validate_bind_host("localhost") == "localhost"
    assert server_module.validate_bind_host("::1") == "::1"


@pytest.mark.parametrize("host", ["", "0.0.0.0", "::", "192.168.1.10", "10.0.0.5", "example.com"])
def test_validate_bind_host_rejects_non_loopback_hosts(host: str) -> None:
    with pytest.raises(server_module.UnsafeBindHostError):
        server_module.validate_bind_host(host)


def test_resolve_json_request_rejects_unused_top_level_fields() -> None:
    status, payload = server_module.resolve_json_request(
        b'{"Provider":"alfresco","auth":{"mode":"windows","target":"tc-wfx/bridge","required":true}}'
    )

    assert status == 400
    assert payload["ok"] is False
    assert payload["message"] == "Invalid credential request."


def test_resolve_json_request_rejects_unused_auth_fields() -> None:
    status, payload = server_module.resolve_json_request(
        b'{"auth":{"mode":"windows","target":"tc-wfx/bridge","required":true,"provider":"alfresco"}}'
    )

    assert status == 400
    assert payload["ok"] is False
    assert payload["message"] == "Invalid credential request."


def test_resolve_paths_include_primary_auth_endpoint_and_legacy_alias() -> None:
    assert server_module.AUTH_RESOLVE_PATH == "/auth/resolve"
    assert server_module.AUTH_RESOLVE_PATH in server_module.RESOLVE_PATHS
    assert server_module.LEGACY_CREDENTIALS_RESOLVE_PATH in server_module.RESOLVE_PATHS