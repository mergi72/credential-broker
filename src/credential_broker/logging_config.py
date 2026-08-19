from __future__ import annotations

import logging
import os
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any


_LOGGING_INITIALIZED = False
_BROKER_FILE_LOGGING_INITIALIZED = False
_DEBUG_FILE_LOGGING_INITIALIZED = False


def debug_enabled(config: Mapping[str, Any] | None) -> bool:
    if not isinstance(config, Mapping):
        return False
    debug = config.get("debug")
    if isinstance(debug, Mapping):
        return debug.get("enable") is True
    return debug is True


def debug_path(config: Mapping[str, Any] | None) -> Path:
    if isinstance(config, Mapping):
        debug = config.get("debug")
        if isinstance(debug, Mapping):
            configured = debug.get("path")
            if isinstance(configured, str) and configured.strip():
                return Path(os.path.expandvars(configured.strip()))
    app_data = os.getenv("APPDATA") or str(Path.home() / "AppData" / "Roaming")
    return Path(app_data) / "Credential Broker" / "logs"


def _configured_level(config: Mapping[str, Any] | None) -> str:
    if isinstance(config, Mapping):
        logging_config = config.get("logging")
        if isinstance(logging_config, Mapping):
            level = logging_config.get("level")
            if isinstance(level, str) and level.strip():
                return level.strip().upper()
    return "INFO"


def _file_handler(path: Path, level: str) -> logging.FileHandler:
    handler = logging.FileHandler(path, encoding="utf-8")
    handler.setLevel(level)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
    return handler


def configure_logging(config: Mapping[str, Any] | None = None) -> None:
    global _LOGGING_INITIALIZED, _BROKER_FILE_LOGGING_INITIALIZED, _DEBUG_FILE_LOGGING_INITIALIZED

    root_logger = logging.getLogger()
    normal_level = _configured_level(config)
    root_level = "DEBUG" if debug_enabled(config) else normal_level

    if _LOGGING_INITIALIZED:
        root_logger.setLevel(root_level)
    else:
        logging.basicConfig(
            level=root_level,
            format="%(asctime)s %(levelname)s %(name)s: %(message)s",
            stream=sys.stdout,
        )
        _LOGGING_INITIALIZED = True

    for handler in root_logger.handlers:
        if isinstance(handler, logging.StreamHandler) and not isinstance(handler, logging.FileHandler):
            handler.setLevel(normal_level)

    log_dir = debug_path(config)
    log_dir.mkdir(parents=True, exist_ok=True)

    if not _BROKER_FILE_LOGGING_INITIALIZED:
        root_logger.addHandler(_file_handler(log_dir / "broker.log", normal_level))
        _BROKER_FILE_LOGGING_INITIALIZED = True

    if debug_enabled(config) and not _DEBUG_FILE_LOGGING_INITIALIZED:
        root_logger.addHandler(_file_handler(log_dir / "broker-debug.log", "DEBUG"))
        _DEBUG_FILE_LOGGING_INITIALIZED = True
