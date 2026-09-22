"""
Hashing password dan pembuatan/verifikasi JWT.

Modul ini sengaja tidak menyentuh database maupun FastAPI — isinya fungsi murni,
supaya bisa diuji sendiri tanpa perlu koneksi apa pun.
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
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 hari

# bcrypt hanya memproses 72 byte pertama. bcrypt 5.x menolak input lebih panjang
# alih-alih memotong diam-diam, jadi batasnya ditegakkan eksplisit di sini.
MAX_PASSWORD_BYTES = 72


def hash_password(password: str) -> str:
    """Ubah password mentah jadi hash bcrypt (salt ikut tertanam di dalamnya)."""
    encoded = password.encode("utf-8")
    if len(encoded) > MAX_PASSWORD_BYTES:
        raise ValueError(f"Password melebihi {MAX_PASSWORD_BYTES} byte.")
    return bcrypt.hashpw(encoded, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    """Cocokkan password mentah dengan hash tersimpan. Tidak pernah melempar."""
    try:
        return bcrypt.checkpw(
            password.encode("utf-8"), password_hash.encode("utf-8")
        )
    except (ValueError, TypeError):
        return False


def create_access_token(user_id: uuid.UUID | str) -> str:
    """Terbitkan JWT bertanda tangan yang mengidentifikasi satu user."""
    if not JWT_SECRET_KEY:
        raise RuntimeError("JWT_SECRET_KEY belum diset di .env")

    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> str | None:
    """Kembalikan user_id kalau token sah, None kalau kedaluwarsa/palsu/rusak."""
    if not JWT_SECRET_KEY:
        raise RuntimeError("JWT_SECRET_KEY belum diset di .env")

    try:
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
    except jwt.InvalidTokenError:
        # Mencakup kedaluwarsa, tanda tangan salah, dan format rusak.
        return None

    return payload.get("sub")
