"""
Pencarian semantik (bagian "R" dari RAG): kalimat pencarian -> vektor -> item
milik user yang vektornya paling dekat. /search/answer menambahkan "A+G":
hasil retrieval dirangkai Gemini jadi jawaban naratif (answerer.py).

POST, bukan GET: kalimat pencarian itu data pribadi. Di GET, ia ikut jadi
bagian URL dan tercatat di log server / proxy. Di body, tidak.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from database import get_db
from deps import get_current_user
from embeddings import embed_one
from models import SavedItem, User
from answerer import generate_answer
from schemas import AnswerRequest, AnswerResponse, ItemPublic, SearchFilters, SearchRequest, SearchResult

router = APIRouter(prefix="/search", tags=["search"])

# Dua saringan relevansi, dikalibrasi dari uji manual (docs/rag-guide.md).
# Keduanya perlu: skor absolut saja gagal karena query pendek/acak menaikkan
# SEMUA skor ("asdfghjkl" dapat 0.61), dan jarak-dari-teratas saja gagal
# karena selalu meloloskan minimal satu hasil walau tidak ada yang relevan.
# Angka ini khusus gemini-embedding-2 -- ganti model = kalibrasi ulang.
MIN_SCORE = 0.60
MAX_GAP_FROM_TOP = 0.06


def retrieve(
    db: Session, user: User, query: str, limit: int, filters: SearchFilters | None = None
) -> list[SearchResult]:
    """Bagian R: dipakai /search (daftar) dan /search/answer (bahan jawaban).

    Hybrid: `filters` (kategori, rentang created_at) masuk WHERE yang sama
    dengan jarak vektor -- satu query SQL, bukan cari dulu lalu saring di
    Python. Saring belakangan akan membuang hasil SETELAH LIMIT dan bisa
    menyisakan nol item padahal yang cocok ada di peringkat ke-11 dst.
    """
    query_vector = embed_one(query.strip())
    if query_vector is None:
        # Tanpa vektor query tidak ada yang bisa dibandingkan. 503 = gangguan
        # sementara di layanan luar, client boleh coba lagi.
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Pencarian sedang tidak tersedia, coba lagi.")

    # HNSW mengambil ef_search (default 40) kandidat terdekat dari SELURUH
    # tabel dulu, baru WHERE user_id disaring setelahnya -- kalau kebanyakan
    # kandidat milik user lain, hasil bisa kurang dari limit bahkan kosong.
    # iterative_scan (pgvector >= 0.8) membuat index terus mencari sampai
    # hasil yang lolos filter cukup. SET LOCAL = cuma berlaku di transaksi ini.
    db.execute(text("SET LOCAL hnsw.iterative_scan = strict_order"))

    distance = SavedItem.embedding.cosine_distance(query_vector)  # operator <=>
    conditions = [
        SavedItem.user_id == user.id,
        SavedItem.embedding.is_not(None),
        distance <= 1 - MIN_SCORE,
    ]
    if filters is not None:
        if filters.category is not None:
            conditions.append(SavedItem.category == filters.category)
        if filters.created_after is not None:
            conditions.append(SavedItem.created_at >= filters.created_after)
        if filters.created_before is not None:
            conditions.append(SavedItem.created_at < filters.created_before)

    rows = db.execute(
        select(SavedItem, distance.label("distance"))
        .where(*conditions)
        .order_by(distance)
        .limit(limit)
    ).all()

    results = []
    for item, dist in rows:
        score = 1 - dist
        if results and score < results[0].score - MAX_GAP_FROM_TOP:
            break  # sudah terurut, sisanya pasti lebih jauh lagi
        results.append(SearchResult(**ItemPublic.model_validate(item).model_dump(), score=round(score, 4)))
    return results


@router.post("", response_model=list[SearchResult])
def search(
    payload: SearchRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return retrieve(db, current_user, payload.query, payload.limit, payload)


# Konteks untuk LLM sengaja kecil: 5 item paling relevan. Lebih banyak =
# lebih banyak token (lambat, mahal) dan item yang relevansinya pinggiran
# malah mengundang model untuk "memaksakan" hubungan yang tidak ada.
ANSWER_CONTEXT_ITEMS = 5
NO_MATCH_ANSWER = "Tidak ada item tersimpan yang cocok dengan pertanyaan ini."


@router.post("/answer", response_model=AnswerResponse)
def search_answer(
    payload: AnswerRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """RAG lengkap: R (retrieve) -> A (masukkan ke prompt) -> G (Gemini menjawab)."""
    sources = retrieve(db, current_user, payload.query, ANSWER_CONTEXT_ITEMS, payload)
    if not sources:
        # Tidak ada bahan = Gemini tidak dipanggil. Kalau dipanggil dengan
        # konteks kosong, ia cenderung menjawab dari pengetahuan umumnya --
        # persis halusinasi yang mau dicegah RAG.
        return AnswerResponse(answer=NO_MATCH_ANSWER, sources=[])
    # answer None = generasi gagal (kuota/timeout). Sumbernya tetap dikirim:
    # daftar hasil tetap berguna tanpa rangkuman.
    return AnswerResponse(answer=generate_answer(payload.query, sources), sources=sources)
