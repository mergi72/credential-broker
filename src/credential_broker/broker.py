from __future__ import annotations

from collections.abc import Callable

from credential_broker.models import AuthContext, CredentialRequest, CredentialResponse
from credential_broker.windows_credential_manager import CredentialBrokerError, CredentialNotFoundError, WindowsCredential, read_windows_credential

CredentialResolver = Callable[[CredentialRequest], CredentialResponse]


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

    try:
        credential = read_windows_credential(target)
    except CredentialNotFoundError as exc:
        if request.auth.required:
            return CredentialResponse(ok=False, message=str(exc))
        return _none_response(message=str(exc))
    except CredentialBrokerError as exc:
        return CredentialResponse(ok=False, message=str(exc))

    return CredentialResponse(ok=True, source="windows", auth=_auth_context_from_windows_credential(credential))


_RESOLVERS: dict[str, CredentialResolver] = {
    "windows": resolve_windows,
}


def resolve_credentials(request: CredentialRequest) -> CredentialResponse:
    mode = request.auth.mode.strip().lower()
    if mode == "none":
        return _none_response()

    resolver = _RESOLVERS.get(mode)
    if resolver is None:
        if request.auth.required:
            return CredentialResponse(ok=False, message=f"Unsupported credential mode: {request.auth.mode}")
        return _none_response()

    return resolver(request)
