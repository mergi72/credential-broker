from __future__ import annotations

import ipaddress
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from pydantic import ValidationError

from credential_broker import __version__
from credential_broker.broker import resolve_credentials
from credential_broker.models import CredentialRequest

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8776
AUTH_RESOLVE_PATH = "/auth/resolve"
LEGACY_CREDENTIALS_RESOLVE_PATH = "/credentials/resolve"
RESOLVE_PATHS = {AUTH_RESOLVE_PATH, LEGACY_CREDENTIALS_RESOLVE_PATH}
ALLOWED_HOST_NAMES = {"localhost"}

SENSITIVE_LOG_KEYS = {"password", "passwd", "secret", "token", "api_key", "apikey", "access_token", "refresh_token"}
MASKED_LOG_VALUE = "***"


def sanitize_request_for_logging(value: Any) -> Any:
    if isinstance(value, bytes):
        return sanitize_request_for_logging(value.decode("utf-8", errors="replace"))
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return value
        return sanitize_request_for_logging(parsed)
    if isinstance(value, dict):
        sensitive_error_input = False
        loc = value.get("loc")
        if isinstance(loc, (list, tuple)):
            sensitive_error_input = any(str(part).lower() in SENSITIVE_LOG_KEYS for part in loc)

        sanitized: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            if key_text.lower() in SENSITIVE_LOG_KEYS or (key_text == "input" and sensitive_error_input):
                sanitized[key_text] = MASKED_LOG_VALUE
            else:
                sanitized[key_text] = sanitize_request_for_logging(item)
        return sanitized
    if isinstance(value, list):
        return [sanitize_request_for_logging(item) for item in value]
    if isinstance(value, tuple):
        return [sanitize_request_for_logging(item) for item in value]
    return value


def _format_for_log(value: Any) -> str:
    return json.dumps(_json_safe(sanitize_request_for_logging(value)), ensure_ascii=False, sort_keys=True)


class UnsafeBindHostError(ValueError):
    pass


def validate_bind_host(host: str) -> str:
    normalized = (host or "").strip()
    if not normalized:
        raise UnsafeBindHostError("Credential Broker bind host must not be empty. Use 127.0.0.1, localhost, or ::1.")

    if normalized.lower() in ALLOWED_HOST_NAMES:
        return normalized

    try:
        address = ipaddress.ip_address(normalized)
    except ValueError as exc:
        raise UnsafeBindHostError(
            f"Refusing to bind Credential Broker to non-loopback host '{host}'. Use 127.0.0.1, localhost, or ::1."
        ) from exc

    if not address.is_loopback:
        raise UnsafeBindHostError(
            f"Refusing to bind Credential Broker to non-loopback host '{host}'. Use 127.0.0.1, localhost, or ::1."
        )
    return normalized


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


def health_payload() -> dict[str, Any]:
    return {"ok": True, "service": "credential-broker", "version": __version__}


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
    normalized: dict[str, Any] = {key: value for key, value in payload.items() if key not in {"auth", "Auth"}}

    if isinstance(auth, dict):
        normalized_auth = {
            key: value
            for key, value in auth.items()
            if key not in {"mode", "Mode", "target", "Target", "targetBase", "target_base", "TargetBase", "required", "Required"}
        }
        normalized_auth.update(
            {
                "mode": _pick(auth, "mode", "Mode"),
                "target": _pick(auth, "target", "Target"),
                "targetBase": _pick(auth, "targetBase", "target_base", "TargetBase"),
                "required": _pick(auth, "required", "Required"),
            }
        )
        if normalized_auth["required"] is None:
            normalized_auth["required"] = True
        normalized["auth"] = normalized_auth
    else:
        normalized["auth"] = auth

    return normalized


def resolve_json_request(raw_body: bytes) -> tuple[int, dict[str, Any]]:
    try:
        raw_payload = json.loads(raw_body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"[WARN] invalid json body={_format_for_log(raw_body)}")
        return 400, {"ok": False, "message": f"Invalid JSON request: {exc}"}

    payload = _normalize_request_payload(raw_payload)
    try:
        request = CredentialRequest.model_validate(payload)
    except ValidationError as exc:
        print(f"[WARN] invalid request body={_format_for_log(raw_body)}")
        print(f"[WARN] normalized payload={_format_for_log(payload)}")
        print(f"[WARN] validation errors={_format_for_log(exc.errors())}")
        return 400, {"ok": False, "message": "Invalid credential request.", "errors": exc.errors()}

    response = resolve_credentials(request)
    status = 200 if response.ok else 404
    return status, response.model_dump(by_alias=True)


class CredentialBrokerHandler(BaseHTTPRequestHandler):
    server_version = "CredentialBroker/1.0"

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        if self.path == "/health":
            self._send_json(200, health_payload())
            return
        self._send_json(404, {"ok": False, "message": "Not found."})

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
        if self.path not in RESOLVE_PATHS:
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


def _serve_until_stopped(server: ThreadingHTTPServer) -> None:
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("[INFO] Credential Broker stop requested.")
    finally:
        server.server_close()
        print("[INFO] Credential Broker stopped.")


def run_server(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> None:
    host = validate_bind_host(host)
    server = ThreadingHTTPServer((host, port), CredentialBrokerHandler)
    print(f"Credential Broker listening on http://{host}:{port}")
    print(f"Health: http://{host}:{port}/health")
    print(f"Resolve: POST http://{host}:{port}{AUTH_RESOLVE_PATH}")
    _serve_until_stopped(server)
