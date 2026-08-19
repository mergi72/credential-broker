from __future__ import annotations

import logging
import time
from collections.abc import Callable

from credential_broker.models import AuthContext, CredentialRequest, CredentialResponse
from credential_broker.windows_credential_manager import CredentialBrokerError, CredentialNotFoundError, WindowsCredential, read_windows_credential

CredentialResolver = Callable[[CredentialRequest], CredentialResponse]
LOGGER = logging.getLogger("credential_broker.broker")


def _none_response(message: str | None = None) -> CredentialResponse:
    return CredentialResponse(ok=True, auth=AuthContext(mode="none"), message=message)


def _auth_context_from_windows_credential(credential: WindowsCredential) -> AuthContext:
    if credential.token is not None:
        return AuthContext(mode="token", token=credential.token, credential_id=credential.target)
    return AuthContext(
        mode="credentials",
        username=credential.username,
        password=credential.password,
        credential_id=credential.target,
    )


def resolve_windows(request: CredentialRequest) -> CredentialResponse:
    target = request.auth.target or request.auth.target_base
    if not target:
        return CredentialResponse(ok=False, message="Windows credential mode requires target or targetBase.")

    started = time.perf_counter()
    LOGGER.info("credential_backend_start backend=windows credential_id=%s", target)
    try:
        credential = read_windows_credential(target)
    except CredentialNotFoundError as exc:
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        LOGGER.warning(
            "credential_backend_done backend=windows credential_id=%s status=not_found elapsed_ms=%s",
            target,
            elapsed_ms,
        )
        if request.auth.required:
            return CredentialResponse(ok=False, message=str(exc))
        return _none_response(message=str(exc))
    except CredentialBrokerError as exc:
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        LOGGER.error(
            "credential_backend_done backend=windows credential_id=%s status=error elapsed_ms=%s error_type=%s",
            target,
            elapsed_ms,
            type(exc).__name__,
        )
        return CredentialResponse(ok=False, message=str(exc))

    elapsed_ms = int((time.perf_counter() - started) * 1000)
    LOGGER.info(
        "credential_backend_done backend=windows credential_id=%s status=ok auth_mode=%s elapsed_ms=%s",
        target,
        "token" if credential.token is not None else "credentials",
        elapsed_ms,
    )
    return CredentialResponse(ok=True, source="windows", auth=_auth_context_from_windows_credential(credential))


_RESOLVERS: dict[str, CredentialResolver] = {
    "windows": resolve_windows,
}


def resolve_credentials(request: CredentialRequest) -> CredentialResponse:
    started = time.perf_counter()
    mode = request.auth.mode.strip().lower()
    credential_id = request.auth.target or request.auth.target_base
    LOGGER.info(
        "credential_resolve_start mode=%s credential_id=%s required=%s",
        mode,
        credential_id,
        request.auth.required,
    )
    try:
        if mode == "none":
            response = _none_response()
        else:
            resolver = _RESOLVERS.get(mode)
            if resolver is None:
                if request.auth.required:
                    response = CredentialResponse(ok=False, message=f"Unsupported credential mode: {request.auth.mode}")
                else:
                    response = _none_response()
            else:
                response = resolver(request)
    except Exception as exc:
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        LOGGER.exception(
            "credential_resolve_failed mode=%s credential_id=%s elapsed_ms=%s error_type=%s",
            mode,
            credential_id,
            elapsed_ms,
            type(exc).__name__,
        )
        raise

    elapsed_ms = int((time.perf_counter() - started) * 1000)
    LOGGER.info(
        "credential_resolve_done mode=%s credential_id=%s ok=%s source=%s auth_mode=%s elapsed_ms=%s",
        mode,
        credential_id,
        response.ok,
        response.source,
        response.auth.mode if response.auth is not None else None,
        elapsed_ms,
    )
    return response
