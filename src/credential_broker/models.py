from __future__ import annotations

from pydantic import BaseModel, Field


class AuthRequirement(BaseModel):
    mode: str = Field(description="Requested credential mode, for example windows, credentials, none.")
    target: str | None = Field(default=None, description="Credential target/name in the backing credential store.")
    target_base: str | None = Field(default=None, alias="targetBase")
    required: bool = True


class UserContext(BaseModel):
    domain: str | None = None
    name: str | None = None


class CredentialRequest(BaseModel):
    provider: str | None = None
    auth: AuthRequirement
    user: UserContext | None = None


class AuthContext(BaseModel):
    mode: str
    username: str | None = None
    password: str | None = None
    token: str | None = None
    credential_id: str | None = None


class CredentialResponse(BaseModel):
    ok: bool
    auth: AuthContext | None = None
    message: str | None = None
