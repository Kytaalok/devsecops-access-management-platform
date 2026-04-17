from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Literal, cast

from fastapi import Header, HTTPException, status
from jwt import InvalidTokenError, PyJWKClient, decode
from jwt.exceptions import PyJWKClientError

from app.config import settings

ALLOWED_ROLES = {"admin", "developer", "viewer"}


@dataclass(frozen=True)
class CurrentUser:
    user_id: str
    username: str
    email: str | None
    role: Literal["admin", "developer", "viewer"]
    claims: dict[str, Any]

    @property
    def is_admin(self) -> bool:
        return self.role == "admin"

    @property
    def is_developer(self) -> bool:
        return self.role == "developer"

    @property
    def is_viewer(self) -> bool:
        return self.role == "viewer"


def _unauthorized(detail: str = "Unauthorized") -> HTTPException:
    return HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=detail)


def _forbidden(detail: str = "Forbidden") -> HTTPException:
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


def _extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise _unauthorized("Missing Authorization header")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise _unauthorized("Invalid Authorization header format")
    return token


def _detect_role_from_claims(claims: dict[str, Any]) -> Literal["admin", "developer", "viewer"]:
    roles: set[str] = set()

    realm_access = claims.get("realm_access")
    if isinstance(realm_access, dict):
        realm_roles = realm_access.get("roles")
        if isinstance(realm_roles, list):
            roles.update(str(role) for role in realm_roles)

    resource_access = claims.get("resource_access")
    if isinstance(resource_access, dict):
        client_claims = resource_access.get(settings.keycloak_client_id)
        if isinstance(client_claims, dict):
            client_roles = client_claims.get("roles")
            if isinstance(client_roles, list):
                roles.update(str(role) for role in client_roles)

    direct_roles = claims.get("roles")
    if isinstance(direct_roles, list):
        roles.update(str(role) for role in direct_roles)

    for candidate in ("admin", "developer", "viewer"):
        if candidate in roles:
            return cast(Literal["admin", "developer", "viewer"], candidate)

    raise _forbidden("No supported role found in token")


def _resolve_jwks_url() -> str:
    if settings.keycloak_jwks_url:
        return settings.keycloak_jwks_url
    return f"{settings.keycloak_issuer.rstrip('/')}/protocol/openid-connect/certs"


@lru_cache(maxsize=1)
def _get_jwk_client() -> PyJWKClient:
    return PyJWKClient(_resolve_jwks_url())


def _decode_token(token: str) -> dict[str, Any]:
    audience = settings.keycloak_audience or settings.keycloak_client_id
    verify_aud = bool(audience)
    try:
        signing_key = _get_jwk_client().get_signing_key_from_jwt(token).key
        return decode(
            token,
            signing_key,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.keycloak_issuer,
            audience=audience,
            options={"verify_aud": verify_aud},
        )
    except (InvalidTokenError, PyJWKClientError):
        raise _unauthorized("Token validation failed")


def _build_dev_user(
    dev_user_id: str | None,
    dev_username: str | None,
    dev_email: str | None,
    dev_role: str | None,
) -> CurrentUser:
    raw_role = (dev_role or "developer").strip().lower()
    role = cast(Literal["admin", "developer", "viewer"], raw_role)
    if role not in ALLOWED_ROLES:
        raise _unauthorized("Unsupported role in development headers")

    user_id = (dev_user_id or "dev-user-1").strip()
    username = (dev_username or "devuser").strip()
    email = (dev_email or "devuser@example.com").strip()

    return CurrentUser(
        user_id=user_id,
        username=username,
        email=email,
        role=role,
        claims={"sub": user_id, "preferred_username": username, "email": email, "role": role},
    )


def get_current_user(
    authorization: str | None = Header(default=None),
    x_user_id: str | None = Header(default=None),
    x_username: str | None = Header(default=None),
    x_email: str | None = Header(default=None),
    x_role: str | None = Header(default=None),
) -> CurrentUser:
    if not settings.auth_enabled:
        return _build_dev_user(x_user_id, x_username, x_email, x_role)

    token = _extract_bearer_token(authorization)
    claims = _decode_token(token)
    user_id = str(claims.get("sub") or "")
    username = str(claims.get("preferred_username") or claims.get("email") or user_id)
    email = claims.get("email")
    role = _detect_role_from_claims(claims)

    if not user_id:
        raise _unauthorized("Token does not contain subject")

    return CurrentUser(
        user_id=user_id,
        username=username,
        email=str(email) if email else None,
        role=role,
        claims=claims,
    )


def ensure_any_role(user: CurrentUser, allowed_roles: set[str]) -> None:
    if user.role not in allowed_roles:
        raise _forbidden("Insufficient role permissions")
