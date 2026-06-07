from __future__ import annotations

import argparse
import json
import sys

from credential_broker.broker import resolve_credentials
from credential_broker.models import CredentialRequest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Resolve a credential request from JSON.")
    parser.add_argument("request", nargs="?", help="Credential request JSON. Reads stdin when omitted.")
    args = parser.parse_args(argv)

    raw = args.request if args.request is not None else sys.stdin.read()
    request = CredentialRequest.model_validate_json(raw)
    response = resolve_credentials(request)
    print(json.dumps(response.model_dump(by_alias=True), ensure_ascii=False, indent=2))
    return 0 if response.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
