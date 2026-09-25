"""
Password hashing and JWT creation/verification.

This module deliberately touches neither the database nor FastAPI -- it's all
pure functions, so it can be tested on its own without any connection.
"""

import os
import uuid
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from dotenv import load_dotenv

load_dotenv()

JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

# bcrypt only processes the first 72 bytes. bcrypt 5.x rejects longer input
# instead of silently truncating it, so the limit is enforced explicitly here.
MAX_PASSWORD_BYTES = 72


def hash_password(password: str) -> str:
    """Turn a raw password into a bcrypt hash (the salt is embedded in it)."""
    encoded = password.encode("utf-8")
    if len(encoded) > MAX_PASSWORD_BYTES:
        raise ValueError(f"Password exceeds {MAX_PASSWORD_BYTES} bytes.")
    return bcrypt.hashpw(encoded, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    """Check a raw password against a stored hash. Never raises."""
    try:
        return bcrypt.checkpw(
            password.encode("utf-8"), password_hash.encode("utf-8")
        )
    except (ValueError, TypeError):
        return False


def create_access_token(user_id: uuid.UUID | str) -> str:
    """Issue a signed JWT identifying one user."""
    if not JWT_SECRET_KEY:
        raise RuntimeError("JWT_SECRET_KEY is not set in .env")

    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> str | None:
    """Return the user_id if the token is valid, None if expired/forged/malformed."""
    if not JWT_SECRET_KEY:
        raise RuntimeError("JWT_SECRET_KEY is not set in .env")

    try:
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
    except jwt.InvalidTokenError:
        # Covers expired, bad signature, and malformed.
        return None

    return payload.get("sub")
