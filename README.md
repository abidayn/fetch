# Fetch

**Save links now, find them later by what they were about.**

You save TikToks, Reels, YouTube videos and articles meaning to come back to
them, but the platforms' "saved" lists are flat and unsearchable, and you only
remember the *idea* ("that pasta video from a few weeks ago"), not the title.

Fetch fixes that:

1. **Share** a link from any app to Fetch via Android's share sheet. No typing.
2. The backend **reads** whatever the link exposes, and Gemini writes a title,
   a short summary and a category.
3. **Search** in plain words. Semantic search over embeddings finds items by
   meaning, filterable by category and date, with an optional AI-written
   answer that cites the items it used.

## Install the app

On an Android phone, open
<https://github.com/abidayn/fetch/releases/latest/download/app-release.apk>
and install it. Play Protect will warn that it doesn't know the developer:
tap **More details → Install anyway**. Details: [`docs/operations.md` §5](docs/operations.md#5-installing-on-a-phone).

## How it works

```text
Android share sheet ─▶ Flutter app ─▶ FastAPI backend ─┬─▶ PostgreSQL + pgvector (Supabase)
                                      (Railway)        └─▶ Google Gemini
  save:   POST /items → 201 at once → background: extract → classify → embed
  search: POST /search → embed query → vector search + filters in one SQL query
```

| Part | Stack |
|---|---|
| `mobile/` | Flutter (Android), share-intent capture, secure token storage |
| `backend/` | Python 3.14, FastAPI, SQLAlchemy + Alembic, yt-dlp / oEmbed / Open Graph extraction |
| Database | PostgreSQL with pgvector (HNSW index), Supabase |
| AI | Gemini: classification, `gemini-embedding-2` embeddings, grounded answers |
| Hosting | Railway (backend, Docker), GitHub Actions → GitHub Releases (APK) |

## Develop

```bash
# backend (from backend/)
python -m venv venv && venv/Scripts/python.exe -m pip install -r requirements.txt
cp .env.example .env   # GEMINI_API_KEY, DATABASE_URL, JWT_SECRET_KEY
venv/Scripts/python.exe -m uvicorn main:app --reload

# mobile (from mobile/)
flutter pub get && flutter run
```

Note: development uses the **same database as production**. See
[`docs/operations.md`](docs/operations.md) before running scripts.

## Documentation

| File | For |
|---|---|
| [`docs/how-it-works.md`](docs/how-it-works.md) | **Start here**: the whole system explained, from the big picture to AI and RAG |
| [`CLAUDE.md`](CLAUDE.md) | Working in the code: commands, architecture, invariants, gotchas |
| [`docs/operations.md`](docs/operations.md) | Deploying the backend, releasing the app, maintenance scripts |
| [`docs/decisions.md`](docs/decisions.md) | Why things are built this way, with the measurements behind them |
| [`docs/data-model.md`](docs/data-model.md) | Database schema (source of truth for the models) |
| [`docs/roadmap.md`](docs/roadmap.md) | Open work and planned features |
