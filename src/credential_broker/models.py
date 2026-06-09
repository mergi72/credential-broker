from __future__ import annotations

from typing import Self

from pydantic import BaseModel, ConfigDict, Field, model_validator


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

    @model_validator(mode="after")
    def validate_secret_shape(self) -> Self:
        mode = self.mode.strip().lower()
        has_user_password = self.username is not None or self.password is not None
        has_token = self.token is not None

        if mode == "none" and (has_user_password or has_token):
            raise ValueError("none auth context must not include username, password, or token")
        if mode == "credentials":
            if has_token:
                raise ValueError("credentials auth context must not include token")
            if self.username is None or self.password is None:
                raise ValueError("credentials auth context requires username and password")
        if mode == "token":
            if has_user_password:
                raise ValueError("token auth context must not include username or password")
            if self.token is None:
                raise ValueError("token auth context requires token")
        return self


class CredentialResponse(BaseModel):
    ok: bool
    auth: AuthContext | None = None
    message: str | None = None
