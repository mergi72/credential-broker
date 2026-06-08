from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class AuthRequirement(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: str = Field(description="Requested credential mode, for example windows, credentials, none.")
    target: str | None = Field(default=None, description="Credential target/name in the backing credential store.")
    target_base: str | None = Field(default=None, alias="targetBase")
    required: bool = True


class CredentialRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    auth: AuthRequirement


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
