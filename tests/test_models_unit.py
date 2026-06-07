from __future__ import annotations

import pytest

from credential_broker.models import CredentialRequest


pytestmark = pytest.mark.unit


def test_auth_requirement_accepts_target_base_alias() -> None:
    request = CredentialRequest.model_validate(
        {
            "provider": "edocat",
            "auth": {
                "mode": "windows",
                "targetBase": "example/base",
                "required": True,
            },
        }
    )

    assert request.provider == "edocat"
    assert request.auth.target_base == "example/base"
