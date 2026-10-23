import time
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import PlainTextResponse
from starlette.routing import Route
from starlette.testclient import TestClient

from spark_mcp.server import RequireAccess

TEAM_DOMAIN = "example.cloudflareaccess.com"
AUDIENCE = "spark-aud"

ACCESS_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class AccessKeys:
    """Resolves every assertion to Access's public key, as PyJWKClient would."""

    def get_signing_key_from_jwt(self, _assertion: str) -> jwt.PyJWK:
        return jwt.PyJWK(RSAAlgorithm.to_jwk(ACCESS_KEY.public_key(), as_dict=True))


def assertion(key: rsa.RSAPrivateKey = ACCESS_KEY, **claims: Any) -> str:
    now = int(time.time())
    payload = {
        "iss": f"https://{TEAM_DOMAIN}",
        "aud": [AUDIENCE],
        "iat": now,
        "exp": now + 300,
        "email": "owner@example.com",
    }
    return jwt.encode(payload | claims, key, algorithm="RS256")


@pytest.fixture
def client() -> TestClient:
    async def ok(_: Request) -> PlainTextResponse:
        return PlainTextResponse("ok")

    access = RequireAccess(
        Starlette(routes=[Route("/mcp", ok, methods=["POST"])]), TEAM_DOMAIN, AUDIENCE
    )
    access.keys = AccessKeys()  # pyright: ignore[reportAttributeAccessIssue]
    return TestClient(access)


def status(client: TestClient, value: str | None) -> int:
    headers = {} if value is None else {"Cf-Access-Jwt-Assertion": value}
    return client.post("/mcp", headers=headers).status_code


def test_admits_an_assertion_for_this_application(client: TestClient) -> None:
    assert status(client, assertion()) == 200


@pytest.mark.parametrize(
    "value",
    [
        None,
        "not-a-jwt",
        assertion(aud=["another-application"]),
        assertion(iss="https://another-team.cloudflareaccess.com"),
        assertion(exp=int(time.time()) - 60),
        assertion(key=OTHER_KEY),
    ],
    ids=["missing", "malformed", "other-application", "other-team", "expired", "other-signer"],
)
def test_rejects(client: TestClient, value: str | None) -> None:
    assert status(client, value) == 401
