"""
Semantic search (the "R" of RAG): search query -> vector -> the user's items
whose vectors are closest. /search/answer adds the "A+G": Gemini turns the
retrieved items into a narrative answer (answerer.py).

POST, not GET: a search query is personal data. With GET it becomes part of
the URL and ends up in server / proxy logs. In the body, it doesn't.
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

# Two relevance filters, calibrated from manual testing (docs/decisions.md).
# Both are needed: an absolute score alone fails because short/random queries
# raise ALL scores ("asdfghjkl" scores 0.61), and distance-from-top alone
# fails because it always lets at least one result through even when nothing
# is relevant. These numbers are specific to gemini-embedding-2 -- change the
# model = recalibrate.
MIN_SCORE = 0.60
MAX_GAP_FROM_TOP = 0.06


def retrieve(
    db: Session, user: User, query: str, limit: int, filters: SearchFilters | None = None
) -> list[SearchResult]:
    """The R part: used by /search (the list) and /search/answer (answer material).

    Hybrid: `filters` (category, created_at range) go into the same WHERE as
    the vector distance -- one SQL query, not search-then-filter in Python.
    Filtering afterwards would drop results AFTER the LIMIT and could leave
    zero items even though matches exist at rank 11 and beyond.
    """
    query_vector = embed_one(query.strip())
    if query_vector is None:
        # Without a query vector there's nothing to compare. 503 = a transient
        # problem in an external service, the client may retry.
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Search is unavailable right now, try again.")

    # HNSW first takes the ef_search (default 40) nearest candidates from the
    # WHOLE table, and only then filters by user_id -- if most candidates
    # belong to other users, results can fall short of the limit or be empty.
    # iterative_scan (pgvector >= 0.8) makes the index keep searching until
    # enough results pass the filter. SET LOCAL = applies to this transaction only.
    db.execute(text("SET LOCAL hnsw.iterative_scan = strict_order"))

    distance = SavedItem.embedding.cosine_distance(query_vector)  # the <=> operator
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
            break  # already sorted, everything after this is even further away
        results.append(SearchResult(**ItemPublic.model_validate(item).model_dump(), score=round(score, 4)))
    return results


@router.post("", response_model=list[SearchResult])
def search(
    payload: SearchRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return retrieve(db, current_user, payload.query, payload.limit, payload)


# The LLM context is deliberately small: the 5 most relevant items. More =
# more tokens (slower, costlier), and marginally relevant items tempt the
# model to "force" connections that aren't there.
ANSWER_CONTEXT_ITEMS = 5
NO_MATCH_ANSWER = "None of your saved items match this question."


@router.post("/answer", response_model=AnswerResponse)
def search_answer(
    payload: AnswerRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Full RAG: R (retrieve) -> A (put into the prompt) -> G (Gemini answers)."""
    sources = retrieve(db, current_user, payload.query, ANSWER_CONTEXT_ITEMS, payload)
    if not sources:
        # No material = Gemini isn't called. Called with an empty context it
        # tends to answer from general knowledge -- exactly the hallucination
        # RAG is meant to prevent.
        return AnswerResponse(answer=NO_MATCH_ANSWER, sources=[])
    # answer None = generation failed (quota/timeout). The sources are still
    # sent: the result list is useful even without a summary.
    return AnswerResponse(answer=generate_answer(payload.query, sources), sources=sources)
