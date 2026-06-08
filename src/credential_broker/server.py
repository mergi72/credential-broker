from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from pydantic import ValidationError

from credential_broker.broker import resolve_credentials
from credential_broker.models import CredentialRequest

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8776


def _json_safe(value: Any) -> Any:
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    return value


def _json_response(status: int, payload: dict[str, Any]) -> tuple[int, bytes]:
    return status, json.dumps(_json_safe(payload), ensure_ascii=False, indent=2).encode("utf-8")


def _pick(mapping: dict[str, Any], *names: str) -> Any:
    for name in names:
        if name in mapping:
            return mapping[name]
    return None


def _normalize_request_payload(payload: Any) -> Any:
    if not isinstance(payload, dict):
        return payload

    auth = _pick(payload, "auth", "Auth")
    user = _pick(payload, "user", "User")
    normalized: dict[str, Any] = {
        "provider": _pick(payload, "provider", "Provider"),
    }

    if isinstance(auth, dict):
        normalized["auth"] = {
            "mode": _pick(auth, "mode", "Mode"),
            "target": _pick(auth, "target", "Target"),
            "targetBase": _pick(auth, "targetBase", "target_base", "TargetBase"),
            "required": _pick(auth, "required", "Required"),
        }
        if normalized["auth"]["required"] is None:
            normalized["auth"]["required"] = True
    else:
        normalized["auth"] = auth

    if isinstance(user, dict):
        normalized["user"] = {
            "domain": _pick(user, "domain", "Domain"),
            "name": _pick(user, "name", "Name"),
        }
    elif user is not None:
        normalized["user"] = user

    return normalized


def resolve_json_request(raw_body: bytes) -> tuple[int, dict[str, Any]]:
    try:
        raw_payload = json.loads(raw_body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"[WARN] invalid json body={raw_body.decode('utf-8', errors='replace')}")
        return 400, {"ok": False, "message": f"Invalid JSON request: {exc}"}

    payload = _normalize_request_payload(raw_payload)
    try:
        request = CredentialRequest.model_validate(payload)
    except ValidationError as exc:
        print(f"[WARN] invalid request body={raw_body.decode('utf-8', errors='replace')}")
        print(f"[WARN] normalized payload={payload}")
        print(f"[WARN] validation errors={exc.errors()}")
        return 400, {"ok": False, "message": "Invalid credential request.", "errors": exc.errors()}

    response = resolve_credentials(request)
    status = 200 if response.ok else 404
    return status, response.model_dump(by_alias=True)


class CredentialBrokerHandler(BaseHTTPRequestHandler):
    server_version = "CredentialBroker/0.1"

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        if self.path == "/health":
            self._send_json(200, {"ok": True, "service": "credential-broker"})
            return
        self._send_json(404, {"ok": False, "message": "Not found."})

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
        if self.path != "/credentials/resolve":
            self._send_json(404, {"ok": False, "message": "Not found."})
            return

        content_length = int(self.headers.get("Content-Length") or "0")
        raw_body = self.rfile.read(content_length)
        status, payload = resolve_json_request(raw_body)
        auth = payload.get("auth") if isinstance(payload.get("auth"), dict) else None
        credential_id = auth.get("credential_id") if isinstance(auth, dict) else None
        print(f"[INFO] resolve status={status} ok={payload.get('ok')} credential_id={credential_id}")
        self._send_json(status, payload)

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        status, body = _json_response(status, payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def run_server(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> None:
    server = ThreadingHTTPServer((host, port), CredentialBrokerHandler)
    print(f"Credential Broker listening on http://{host}:{port}")
    print(f"Health: http://{host}:{port}/health")
    print(f"Resolve: POST http://{host}:{port}/credentials/resolve")
    server.serve_forever()
