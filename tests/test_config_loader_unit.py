from __future__ import annotations

import json

import pytest

from credential_broker.config_loader import load_config, server_host, server_port


pytestmark = pytest.mark.unit


def test_load_config_returns_defaults_when_machine_config_missing(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    machine_dir = tmp_path / "machine"
    user_dir = tmp_path / "user"
    user_dir.mkdir()
    (user_dir / "broker.local.json").write_text(json.dumps({"server": {"port": 9999}}), encoding="utf-8")
    monkeypatch.setenv("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", str(machine_dir))
    monkeypatch.setenv("CREDENTIAL_BROKER_USER_CONFIG_DIR", str(user_dir))

    config = load_config()

    assert server_host(config) == "127.0.0.1"
    assert server_port(config) == 8776
    assert config["debug"] == {"enable": False, "path": r"%APPDATA%\Credential Broker\logs"}


def test_load_config_merges_user_local_over_machine(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    machine_dir = tmp_path / "machine"
    user_dir = tmp_path / "user"
    machine_dir.mkdir()
    user_dir.mkdir()
    (machine_dir / "broker.json").write_text(
        json.dumps({"server": {"host": "127.0.0.1", "port": 8776}, "logging": {"level": "info"}}),
        encoding="utf-8",
    )
    (user_dir / "broker.local.json").write_text(json.dumps({"server": {"port": 8766}}), encoding="utf-8")
    monkeypatch.setenv("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", str(machine_dir))
    monkeypatch.setenv("CREDENTIAL_BROKER_USER_CONFIG_DIR", str(user_dir))

    config = load_config()

    assert server_host(config) == "127.0.0.1"
    assert server_port(config) == 8766
    assert config["logging"]["level"] == "info"


def test_load_config_accepts_supported_windows_backend(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    machine_dir = tmp_path / "machine"
    user_dir = tmp_path / "user"
    machine_dir.mkdir()
    user_dir.mkdir()
    (machine_dir / "broker.json").write_text(
        json.dumps({"credentials": {"backend": "windows"}}), encoding="utf-8"
    )
    monkeypatch.setenv("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", str(machine_dir))
    monkeypatch.setenv("CREDENTIAL_BROKER_USER_CONFIG_DIR", str(user_dir))

    config = load_config()

    assert config["credentials"]["backend"] == "windows"


def test_load_config_rejects_unsupported_backend(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    machine_dir = tmp_path / "machine"
    user_dir = tmp_path / "user"
    machine_dir.mkdir()
    user_dir.mkdir()
    (machine_dir / "broker.json").write_text(
        json.dumps({"credentials": {"backend": "unix"}}), encoding="utf-8"
    )
    monkeypatch.setenv("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", str(machine_dir))
    monkeypatch.setenv("CREDENTIAL_BROKER_USER_CONFIG_DIR", str(user_dir))

    with pytest.raises(ValueError, match="credentials.backend"):
        load_config()
