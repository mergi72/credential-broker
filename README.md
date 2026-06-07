# Credential Broker

Credential Broker is a per-user local service that exposes controlled access to user-scoped credentials for trusted local applications and system services.

It is not a LocalSystem or LocalService Windows Service. It must run in the interactive user's context so it can access that user's Windows Credential Manager. System services can use the broker as a controlled user-context credential boundary instead of reading user secrets directly.

Generic user-context credential broker for applications and services that need credentials without knowing where secrets are stored.

The broker owns credential resolution. Callers describe what they need, and the broker returns a bridge-compatible auth context.

## Goals

- Run in the interactive user context.
- Start after user logon, for example as a scheduled task or user agent.
- Resolve secrets from Windows Credential Manager.
- Provide controlled access to user-scoped credentials for trusted local callers.
- Keep service processes decoupled from user-scoped credential stores.
- Never run as LocalSystem or LocalService when user credentials are required.
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
