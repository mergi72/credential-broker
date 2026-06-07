from __future__ import annotations

import ctypes
import json
import sys
from ctypes import wintypes
from dataclasses import dataclass


class CredentialBrokerError(Exception):
    """Base credential broker error."""


class CredentialNotFoundError(CredentialBrokerError):
    """Raised when a requested credential target does not exist."""


@dataclass(frozen=True)
class WindowsCredential:
    target: str
    username: str | None
    password: str | None = None
    token: str | None = None


class _FILETIME(ctypes.Structure):
    _fields_ = [("dwLowDateTime", wintypes.DWORD), ("dwHighDateTime", wintypes.DWORD)]


class _CREDENTIALW(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD),
        ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR),
        ("Comment", wintypes.LPWSTR),
        ("LastWritten", _FILETIME),
        ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(wintypes.BYTE)),
        ("Persist", wintypes.DWORD),
        ("AttributeCount", wintypes.DWORD),
        ("Attributes", wintypes.LPVOID),
        ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


CRED_TYPE_GENERIC = 1


def _decode_blob(pointer: ctypes.POINTER(wintypes.BYTE), size: int) -> str:
    if not pointer or size <= 0:
        return ""
    raw = ctypes.string_at(pointer, size)
    try:
        return raw.decode("utf-16-le")
    except UnicodeDecodeError:
        return raw.decode("utf-8", errors="replace")


def read_windows_credential(target: str) -> WindowsCredential:
    if sys.platform != "win32":
        raise CredentialBrokerError("Windows Credential Manager is available only on Windows.")

    advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
    cred_read = advapi32.CredReadW
    cred_read.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(_CREDENTIALW))]
    cred_read.restype = wintypes.BOOL
    cred_free = advapi32.CredFree
    cred_free.argtypes = [wintypes.LPVOID]
    cred_free.restype = None

    credential_pointer = ctypes.POINTER(_CREDENTIALW)()
    ok = cred_read(target, CRED_TYPE_GENERIC, 0, ctypes.byref(credential_pointer))
    if not ok:
        raise CredentialNotFoundError(f"Credential not found: {target}")

    try:
        credential = credential_pointer.contents
        secret = _decode_blob(credential.CredentialBlob, int(credential.CredentialBlobSize))
        username = credential.UserName or None
        if secret:
            try:
                payload = json.loads(secret)
            except json.JSONDecodeError:
                payload = None
            if isinstance(payload, dict):
                return WindowsCredential(
                    target=target,
                    username=str(payload.get("username")) if payload.get("username") is not None else username,
                    password=str(payload.get("password")) if payload.get("password") is not None else None,
                    token=str(payload.get("token")) if payload.get("token") is not None else None,
                )
        return WindowsCredential(target=target, username=username, password=secret or None)
    finally:
        cred_free(credential_pointer)
