from __future__ import annotations

from credential_broker.models import AuthContext, CredentialRequest, CredentialResponse
from credential_broker.windows_credential_manager import CredentialBrokerError, CredentialNotFoundError, read_windows_credential


def resolve_credentials(request: CredentialRequest) -> CredentialResponse:
    mode = request.auth.mode.strip().lower()
    if mode == "none":
        return CredentialResponse(ok=True, auth=AuthContext(mode="none"))
    if mode != "windows":
        if request.auth.required:
            return CredentialResponse(ok=False, message=f"Unsupported credential mode: {request.auth.mode}")
        return CredentialResponse(ok=True, auth=AuthContext(mode="none"))

    target = request.auth.target or request.auth.target_base
    if not target:
        return CredentialResponse(ok=False, message="Windows credential mode requires target or targetBase.")

    try:
        credential = read_windows_credential(target)
    except CredentialNotFoundError as exc:
        if request.auth.required:
            return CredentialResponse(ok=False, message=str(exc))
        return CredentialResponse(ok=True, auth=AuthContext(mode="none"), message=str(exc))
    except CredentialBrokerError as exc:
        return CredentialResponse(ok=False, message=str(exc))

    return CredentialResponse(
        ok=True,
        auth=AuthContext(
            mode="credentials",
            username=credential.username,
            password=credential.password,
            token=credential.token,
            credential_id=credential.target,
        ),
    )
