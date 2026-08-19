from __future__ import annotations

import argparse
import json
import sys

from credential_broker.broker import resolve_credentials
from credential_broker.config_loader import load_config, server_host, server_port
from credential_broker.logging_config import configure_logging
from credential_broker.models import CredentialRequest
from credential_broker.server import run_server


def _resolve(raw: str) -> int:
    request = CredentialRequest.model_validate_json(raw)
    response = resolve_credentials(request)
    print(json.dumps(response.model_dump(by_alias=True), ensure_ascii=False, indent=2))
    return 0 if response.ok else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Resolve credential requests.")
    subparsers = parser.add_subparsers(dest="command")

    resolve_parser = subparsers.add_parser("resolve", help="Resolve a credential request from JSON.")
    resolve_parser.add_argument("request", nargs="?", help="Credential request JSON. Reads stdin when omitted.")

    serve_parser = subparsers.add_parser("serve", help="Run the local credential broker HTTP API.")
    serve_parser.add_argument("--host", default=None, help="Bind host. Overrides broker.json server.host.")
    serve_parser.add_argument("--port", type=int, default=None, help="Bind port. Overrides broker.json server.port.")

    args = parser.parse_args(argv)
    config = load_config()
    configure_logging(config)

    if args.command == "serve":
        host = args.host or server_host(config)
        port = args.port if args.port is not None else server_port(config)
        run_server(host=host, port=port)
        return 0

    if args.command == "resolve":
        raw = args.request if args.request is not None else sys.stdin.read()
        return _resolve(raw)

    if argv and argv[0].strip().startswith("{"):
        return _resolve(argv[0])

    raw = sys.stdin.read()
    if raw.strip():
        return _resolve(raw)

    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
