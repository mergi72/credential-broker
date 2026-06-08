from __future__ import annotations

import pytest
from pydantic import ValidationError

from credential_broker.models import CredentialRequest


pytestmark = pytest.mark.unit


def test_auth_requirement_accepts_target_base_alias() -> None:
    request = CredentialRequest.model_validate(
        {
            "auth": {
                "mode": "windows",
                "targetBase": "example/base",
                "required": True,
            },
        }
    )

    assert request.auth.target_base == "example/base"


@pytest.mark.parametrize("field", ["provider", "user"])
def test_credential_request_rejects_unused_fields(field: str) -> None:
    with pytest.raises(ValidationError):
        CredentialRequest.model_validate(
            {
                field: {},
                "auth": {
                    "mode": "windows",
                    "target": "tc-wfx/bridge",
                    "required": True,
                },
            }
        )
