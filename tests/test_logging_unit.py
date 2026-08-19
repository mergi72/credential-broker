from __future__ import annotations

import logging

import pytest

from credential_broker import logging_config


pytestmark = pytest.mark.unit


def _reset_logging(monkeypatch: pytest.MonkeyPatch) -> tuple[logging.Logger, list[logging.Handler]]:
    monkeypatch.setattr(logging_config, "_LOGGING_INITIALIZED", False)
    monkeypatch.setattr(logging_config, "_BROKER_FILE_LOGGING_INITIALIZED", False)
    monkeypatch.setattr(logging_config, "_DEBUG_FILE_LOGGING_INITIALIZED", False)
    root_logger = logging.getLogger()
    original_handlers = list(root_logger.handlers)
    for handler in original_handlers:
        root_logger.removeHandler(handler)
    return root_logger, original_handlers


def _restore_logging(
    root_logger: logging.Logger,
    original_handlers: list[logging.Handler],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    for handler in list(root_logger.handlers):
        root_logger.removeHandler(handler)
        handler.close()
    for handler in original_handlers:
        root_logger.addHandler(handler)
    monkeypatch.setattr(logging_config, "_LOGGING_INITIALIZED", False)
    monkeypatch.setattr(logging_config, "_BROKER_FILE_LOGGING_INITIALIZED", False)
    monkeypatch.setattr(logging_config, "_DEBUG_FILE_LOGGING_INITIALIZED", False)


def test_configure_logging_writes_operational_log_when_debug_is_disabled(
    tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root_logger, original_handlers = _reset_logging(monkeypatch)
    try:
        logging_config.configure_logging(
            {"logging": {"level": "info"}, "debug": {"enable": False, "path": str(tmp_path)}}
        )
        logging.getLogger("credential_broker.test").info("hello broker log")

        assert "hello broker log" in (tmp_path / "broker.log").read_text(encoding="utf-8")
        assert not (tmp_path / "broker-debug.log").exists()
    finally:
        _restore_logging(root_logger, original_handlers, monkeypatch)


def test_configure_logging_writes_debug_log_when_enabled(tmp_path, monkeypatch: pytest.MonkeyPatch) -> None:
    root_logger, original_handlers = _reset_logging(monkeypatch)
    try:
        logging_config.configure_logging(
            {"logging": {"level": "info"}, "debug": {"enable": True, "path": str(tmp_path)}}
        )
        logging.getLogger("credential_broker.test").debug("hello broker debug")

        assert "hello broker debug" in (tmp_path / "broker-debug.log").read_text(encoding="utf-8")
        assert "hello broker debug" not in (tmp_path / "broker.log").read_text(encoding="utf-8")
    finally:
        _restore_logging(root_logger, original_handlers, monkeypatch)
