from __future__ import annotations

import json
import os
from collections.abc import Mapping
from pathlib import Path
from typing import Any

CONFIG_FILE_NAME = "broker.json"
USER_CONFIG_FILE_NAME = "broker.local.json"
MACHINE_CONFIG_ENV = "CREDENTIAL_BROKER_MACHINE_CONFIG_DIR"
USER_CONFIG_ENV = "CREDENTIAL_BROKER_USER_CONFIG_DIR"
APP_DIR_NAME = "Credential Broker"
CONFIG_DIR_NAME = "config"

DEFAULT_CONFIG: dict[str, Any] = {
    "server": {"host": "127.0.0.1", "port": 8776},
    "credentials": {"backend": "windows"},
    "logging": {"level": "info"},
    "debug": {"enable": False, "path": r"%APPDATA%\Credential Broker\logs"},
}


def _default_machine_config_dir() -> Path:
    common_app_data = os.getenv("ProgramData") or os.getenv("CommonProgramData") or r"C:\ProgramData"
    return Path(common_app_data) / APP_DIR_NAME / CONFIG_DIR_NAME


def _default_user_config_dir() -> Path:
    app_data = os.getenv("APPDATA") or str(Path.home() / "AppData" / "Roaming")
    return Path(app_data) / APP_DIR_NAME / CONFIG_DIR_NAME


def machine_config_dir() -> Path:
    configured = os.getenv(MACHINE_CONFIG_ENV)
    return Path(configured) if configured else _default_machine_config_dir()


def user_config_dir() -> Path:
    configured = os.getenv(USER_CONFIG_ENV)
    return Path(configured) if configured else _default_user_config_dir()


def deep_merge(base: Mapping[str, Any], override: Mapping[str, Any]) -> dict[str, Any]:
    merged: dict[str, Any] = dict(base)
    for key, value in override.items():
        existing = merged.get(key)
        if isinstance(existing, Mapping) and isinstance(value, Mapping):
            merged[key] = deep_merge(existing, value)
        else:
            merged[key] = value
    return merged


def _read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"Config file must contain a JSON object: {path}")
    return payload


def load_config() -> dict[str, Any]:
    machine_path = machine_config_dir() / CONFIG_FILE_NAME
    user_path = user_config_dir() / USER_CONFIG_FILE_NAME
    if not machine_path.exists():
        return dict(DEFAULT_CONFIG)
    config = deep_merge(DEFAULT_CONFIG, _read_json(machine_path))
    if user_path.exists():
        config = deep_merge(config, _read_json(user_path))
    return config


def server_host(config: Mapping[str, Any]) -> str:
    server = config.get("server")
    if isinstance(server, Mapping):
        host = server.get("host")
        if isinstance(host, str) and host.strip():
            return host.strip()
    return str(DEFAULT_CONFIG["server"]["host"])


def server_port(config: Mapping[str, Any]) -> int:
    server = config.get("server")
    if isinstance(server, Mapping):
        port = server.get("port")
        if isinstance(port, int) and 0 < port < 65536:
            return port
        if isinstance(port, str) and port.isdigit():
            parsed = int(port)
            if 0 < parsed < 65536:
                return parsed
    return int(DEFAULT_CONFIG["server"]["port"])
