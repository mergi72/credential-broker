# Credential Broker

Generic user-context credential broker for applications and services that need credentials without knowing where secrets are stored.

The broker owns credential resolution. Callers describe what they need, and the broker returns a bridge-compatible auth context.

## Goals

- Run in the interactive user context.
- Resolve secrets from Windows Credential Manager.
- Keep service processes decoupled from user-scoped credential stores.
- Use small JSON request/response contracts.
- Stay application-agnostic: no DMS, TC-WFX, or provider-specific assumptions in the core layer.

## Contract

Request:

```json
{
  "provider": "alfresco",
  "auth": {
    "mode": "windows",
    "target": "tc-wfx/bridge",
    "required": true
  },
  "user": {
    "domain": "DOMAIN",
    "name": "user"
  }
}
```

Response:

```json
{
  "ok": true,
  "auth": {
    "mode": "credentials",
    "username": "user@example.com",
    "password": "secret"
  }
}
```

## Initial Scope

- Windows only.
- Windows Credential Manager backend.
- Library and CLI first; HTTP/IPC can be added later.
- No UI login flow in the first version.

## Development

```powershell
python -m venv .venv312
.\.venv312\Scripts\activate
pip install -e .[dev]
pytest
```
