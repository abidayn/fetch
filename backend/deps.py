"""
Dependency bersama untuk route yang butuh autentikasi.
"""

import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from database import get_db
from models import User
from security import decode_access_token

# auto_error=False supaya kita sendiri yang menentukan bentuk error-nya,
# bukan pesan bawaan FastAPI.
bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Ubah header `Authorization: Bearer <token>` jadi objek User.

    Semua kegagalan menghasilkan 401 yang identik — token hilang, rusak,
    kedaluwarsa, atau menunjuk user yang sudah dihapus. Penyerang tidak perlu
    tahu mana penyebabnya.
    """
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token tidak valid atau sudah kedaluwarsa.",
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
