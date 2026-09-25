"""
Shared dependencies for routes that require authentication.
"""

import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from database import get_db
from models import User
from security import decode_access_token

# auto_error=False so we decide the shape of the error ourselves, rather than
# FastAPI's built-in message.
bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Turn the `Authorization: Bearer <token>` header into a User object.

    Every failure produces the identical 401 -- token missing, malformed,
    expired, or pointing at a deleted user. An attacker doesn't get to learn
    which one it was.
    """
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token.",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None:
        raise unauthorized

    user_id = decode_access_token(credentials.credentials)
    if user_id is None:
        raise unauthorized

    try:
        user_uuid = uuid.UUID(user_id)
    except ValueError:
        raise unauthorized

    user = db.get(User, user_uuid)
    if user is None:
        raise unauthorized

    return user
