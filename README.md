# Credential Broker

[![CI](https://github.com/mergi72/credential-broker/actions/workflows/ci.yml/badge.svg)](https://github.com/mergi72/credential-broker/actions/workflows/ci.yml)
[![Status](https://img.shields.io/badge/Status-1.0-brightgreen)](https://github.com/mergi72/credential-broker)
[![Broker](https://img.shields.io/badge/Broker-v1.1.2-blue)](https://github.com/mergi72/credential-broker/releases/tag/v1.1.2)
[![Setup](https://img.shields.io/badge/Setup-v1.1.2-blueviolet)](https://github.com/mergi72/credential-broker/releases/tag/v1.1.2)

Credential Broker is a per-user local service that exposes controlled access to user-scoped credentials for trusted local applications and system services.

It is not a LocalSystem or LocalService Windows Service. It must run in the interactive user's context so it can access that user's Windows Credential Manager. System services can use the broker as a controlled user-context credential boundary instead of reading user secrets directly.

Generic user-context credential broker for applications and services that need credentials without knowing where secrets are stored.

The broker owns credential resolution. Callers describe what they need, and the broker returns a bridge-compatible auth context.

## Architecture

Credential Broker is intentionally application-agnostic. Callers ask for an auth context; the broker resolves it from a configured credential source.

```text
Application A
Application B
Application C
        |
        v
Credential Broker
        |
        v
Credential Source
```

Or, abstractly:

```text
Caller
  |
  v
Broker
  |
  v
Credential Provider
```

## Goals

- Run in the interactive user context.
- Start after user logon, for example as a scheduled task or user agent.
- Resolve secrets from Windows Credential Manager.
- Provide controlled access to user-scoped credentials for trusted local callers.
- Keep service processes decoupled from user-scoped credential stores.
- Never run as LocalSystem or LocalService when user credentials are required.
- Use small JSON request/response contracts.
- Stay application-agnostic: no DMS, TC-WFX, or provider-specific assumptions in the core layer.

## Local API

Default endpoint:

```text
http://127.0.0.1:8776
```

The broker is localhost-only by design. It refuses to bind to non-loopback hosts such as `0.0.0.0`, `::`, or LAN IP addresses. Allowed bind hosts are `127.0.0.1`, `localhost`, and `::1`.

The HTTP API currently trusts local processes running in the interactive user's trusted environment. Loopback binding prevents network access, but it does not authenticate a Windows user or process. Do not expose the Broker across user or service-identity boundaries until caller authentication and credential-target policy are implemented.

The only currently supported credential backend is `windows`. Other backend names are rejected during configuration loading; the setting is retained as the extension point for future local credential providers.

Operational and optional debug logs use the same configuration contract as VFS Provider Bridge:

```json
"debug": {
  "enable": true,
  "path": "%APPDATA%\\Credential Broker\\logs"
}
```

`broker.log` contains normal operational messages. Setting `enable` to `true` additionally creates
`broker-debug.log` with DEBUG-level messages. Credential secrets are masked before request validation errors are logged.
Every HTTP request records its method, path, status, loopback client and caller identity. VFS components may identify
themselves with the optional `X-VFS-Component` request header; other callers are identified by a sanitized `User-Agent`.

Endpoints:

```text
GET  /health
POST /auth/resolve
```

`/credentials/resolve` is kept as a temporary compatibility alias for older local callers.

Run the local broker:

```powershell
credential-broker serve
```

Or from source:

```powershell
python -m credential_broker.cli serve
```

## Contract

Request:

```json
{
  "auth": {
    "mode": "windows",
    "target": "tc-wfx/bridge",
    "required": true
  }
}
```

Response:

```json
{
  "ok": true,
  "source": "windows",
  "auth": {
    "mode": "credentials",
    "username": "user@example.com",
    "password": "secret",
    "credential_id": "tc-wfx/bridge"
  }
}
```

CLI resolve:

```powershell
credential-broker resolve '{"auth":{"mode":"windows","target":"tc-wfx/bridge","required":true}}'
```

HTTP resolve:

```powershell
Invoke-RestMethod -Method Post `
  -Uri http://127.0.0.1:8776/auth/resolve `
  -ContentType application/json `
  -Body '{"auth":{"mode":"windows","target":"tc-wfx/bridge","required":true}}'
```

## Initial Scope

- Windows only.
- Windows Credential Manager backend.
- Library, CLI and local HTTP API first; IPC can be added later.
- No UI login flow in the first version.

## Development

```powershell
python -m venv .venv312
.\.venv312\Scripts\activate
pip install -e .[dev]
pytest
```

## Windows Installer

Build the standalone per-user broker installer:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-broker-installer.ps1
```

The installer installs only Credential Broker. It does not install or configure DMS Provider Bridge, Total Commander, or the WFX plugin.

Installed files:

```text
%LOCALAPPDATA%\Credential Broker\credential-broker.exe
%LOCALAPPDATA%\Credential Broker\config\broker.json
%LOCALAPPDATA%\Credential Broker\logs\
```

It creates a per-user Scheduled Task named `CredentialBroker` and starts the broker in the interactive user context.

