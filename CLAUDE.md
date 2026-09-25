# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Fetch: a personal "save links, find them later" app. Links are captured from the Android share sheet in a Flutter app (`mobile/`), sent to a FastAPI backend (`backend/`), enriched in the background (metadata scraping → Gemini classification → embedding), and retrieved via semantic search / RAG answers over Postgres + pgvector.

**Everything is in English**: code comments, docstrings, UI text, API error messages, Gemini prompts, and docs. Gemini writes summaries and answers in English; titles keep the content's original language. Comments explain *why* in detail — match that density.

## Documentation map

| File | Holds | Update when |
|---|---|---|
| `README.md` | What Fetch is, install, quick start | the pitch or setup changes |
| `docs/how-it-works.md` | Onboarding guide: helicopter view → system design → AI → RAG → failure map → AI-fallback decision lens, traced with one real item | flows, models, thresholds, failure behaviour or file layout change |
| `docs/operations.md` | Railway deploy, APK release + signing, maintenance scripts, phone install | a deploy/release step changes |
| `docs/decisions.md` | Why things are built this way, with measurements (search calibration, model choices, hosting) | you make or reverse a design decision |
| `docs/data-model.md` | Schema **source of truth** — `models.py` follows it | the schema changes: edit this first, then `models.py`, then a migration |
| `docs/roadmap.md` | Open work only (done work lives in git history) | work is finished or discovered |

Don't add task logs or extra learning notes to `docs/` (`how-it-works.md` is the one onboarding guide — extend it instead); don't record fixes in docs — that's what commits are for.

## Commands

### Backend (`backend/`, Python 3.14, venv at `backend/venv`)

```bash
venv/Scripts/python.exe -m pip install -r requirements.txt
venv/Scripts/python.exe -m uvicorn main:app --reload        # dev server on :8000
venv/Scripts/python.exe -m alembic upgrade head              # apply migrations
venv/Scripts/python.exe -m alembic revision --autogenerate -m "..."
venv/Scripts/python.exe backfill_enrichment.py               # re-run unfinished enrichment
venv/Scripts/python.exe backfill_enrichment.py --ids <uuid>…  # force re-enrich specific items from scratch
venv/Scripts/python.exe backfill_enrichment.py --reclassify  # re-run Gemini on stored raw_content (after prompt/model changes)
venv/Scripts/python.exe backfill_embeddings.py [--all]       # fill NULL embeddings; --all after changing embedding model
```

Requires `backend/.env` (copy `.env.example`): `GEMINI_API_KEY`, `DATABASE_URL` (plain `postgresql://` — `database.py` rewrites it to the `psycopg` v3 driver), `JWT_SECRET_KEY`. `check_db.py` / `check_gemini.py` are throwaway connectivity checks. There is no backend test suite.

**Dev and production share one Supabase database.** A local server and every backfill script read and write production data, and the Gemini free-tier quota (classifier model: 20 requests/day, 5/min) is shared with the server.

Deployed on **Railway** (Singapore; not Render) via `backend/Dockerfile`, Railway root directory `backend`, single uvicorn worker (limited Supavisor pool; BackgroundTasks run in-process). Production URL: `https://fetch-production-35a4.up.railway.app` (baked into the APK via `API_BASE_URL`). Merging to `main` does not by itself prove production is updated — verify routes with `/openapi.json`. Migrations are not run on deploy; run them from the laptop. Details: `docs/operations.md`.

### Mobile (`mobile/`, Flutter SDK at `C:\flutter`, may not be on PATH)

```bash
flutter pub get
flutter run                                                   # talks to local backend
flutter run --dart-define=API_BASE_URL=https://<backend>      # talks to a deployed backend
flutter analyze
flutter test                                                  # single smoke test
flutter test test/widget_test.dart
```

Without `API_BASE_URL`, `ApiClient` uses `http://10.0.2.2:8000` on Android (emulator alias for host localhost) and `127.0.0.1:8000` elsewhere; a physical device needs the define.

### Release

`.github/workflows/android-release.yml` builds a signed release APK on `v*` tags and attaches it to a GitHub Release. Signing uses `android/app/release.jks`, which only exists in CI (decoded from secrets); local release builds fall back to the debug key (`mobile/android/app/build.gradle.kts`). Build number comes from `github.run_number` so each APK can upgrade the previous one. Keystore and secrets: `docs/operations.md` §4.

## Backend architecture

- `main.py` wires three routers: `routers/auth.py` (register/login, JWT via `security.py`), `routers/items.py` (CRUD), `routers/search.py` (`POST /search`, `POST /search/answer`). Auth is `deps.get_current_user` (Bearer JWT → `User`; every failure is the same 401).
- **Save flow**: `POST /items` stores only the URL and returns 201 immediately, then schedules `enrichment.enrich_item` as a BackgroundTask (with its own DB session). Enrichment = `extraction.extract` (per-platform fallback chains: YouTube yt-dlp → YouTube oEmbed → OG, since YouTube blocks yt-dlp from Railway's datacenter IPs; TikTok oEmbed → `/embed/v2/<id>` page JSON, which also covers photo posts; Instagram OG fetched with the `facebookexternalhit` crawler UA, since normal browsers get an empty JS shell; generic OG. Generic platform titles/descriptions are filtered as junk so Gemini never summarises the platform itself) → `classifier.classify` (Gemini structured output: title, English summary, category) → `embeddings.embed_one` on title+summary.
- **"Never raise" contract**: `extract`, `classify`, `embed*`, and `generate_answer` return thin data or `None` on failure instead of raising. Callers decide what that means (keep NULL for backfill, or return 503 on search). Preserve this when touching them.
- **Processing state is encoded in `raw_content`**, no status column: `NULL` = not yet processed, `""` = processed but nothing extractable, otherwise extracted text. `SavedItem.processed` and `SavedItem.has_content` (lets the app tell "link unreadable" from "AI failed") derive from this; `PATCH /items/{id}` returns 409 while unprocessed (enrichment would overwrite edits). NULL `embedding`/`summary` act as work queues for the backfill scripts.
- **Categories** are a fixed `Literal` in `classifier.py` and served to the app via `GET /items/categories` — that is the single source of truth (no copy in Flutter). `/categories` must stay registered before `/{item_id}`.
- **Editing** title/summary re-embeds the item; a failed re-embed keeps the old vector.
- **Search** (`routers/search.py::retrieve`): cosine distance on pgvector HNSW with filters (category, created_at range) in the same SQL WHERE, `SET LOCAL hnsw.iterative_scan`, and two relevance cutoffs (`MIN_SCORE`, `MAX_GAP_FROM_TOP`) calibrated for `gemini-embedding-2` (evidence in `docs/decisions.md`) — recalibrate if the embedding model changes. `/search/answer` skips Gemini entirely when retrieval returns nothing.
- **Gemini**: one lazy client in `gemini.py` (so Alembic can import models without the API key) with retries on 429/5xx. Classifier and answerer deliberately use different models because free-tier quota is per model. Embedding model/dimension (`embeddings.py`) must match `Vector(768)` in `models.py`; changing either requires a migration plus `backfill_embeddings.py --all`.
- Ownership: other users' items return 404, not 403.

## Mobile architecture

- `lib/api/api_client.dart` is the only place that does HTTP; it attaches the token from `token_storage.dart` (flutter_secure_storage), applies a 30s timeout, and retries once on transient failures (network, 502/503/504) — but **never retries `POST /items`** (could double-save) or register. Errors surface as `ApiException` (`statusCode` 0 = offline/timeout); backend `detail` messages are shown to the user as-is.
- `lib/main.dart` listens for shared links via `receive_sharing_intent` for both warm (stream) and cold-start (`getInitialMedia`) shares, and uses global Navigator/ScaffoldMessenger/HomeScreen keys to show the save sheet and refresh from outside the widget tree. No state-management library.
- Screens in `lib/screens/`, bottom sheets and tiles in `lib/widgets/`.

## Gotchas (each one bit us before)

- **Alembic autogenerate diffs against the database's current state**, not the intended history. A dirty database produced a migration that dropped a stray table and failed on fresh installs. Always read generated migrations before applying.
- **Embeddings: pass each text as its own `types.Content`.** A plain `list[str]` makes `gemini-embedding-2` return one combined vector, silently. `embed()` also checks vector count and length.
- **HNSW operator class must match the query operator** (`vector_cosine_ops` ↔ `<=>`); ordering by `<->` silently falls back to a sequential scan. With few rows the planner uses a seq scan anyway — that's correct.
- **Android splash freeze on cold-start share**: Flutter's implicit splash dismissal doesn't fire when the Activity is launched via the share-sheet trampoline. Fixed with `androidx.core:core-splashscreen` + `installSplashScreen()` in `MainActivity.kt` + `LaunchTheme` extending `Theme.SplashScreen` — don't remove any of the three.
- **`INTERNET` permission must be in the main `AndroidManifest.xml`** — the debug manifest has it, so debug builds work while release builds can't reach the network.
- **Share intent**: `launchMode="singleTask"`, and `ReceiveSharingIntent.instance.reset()` after handling, or the same share is re-read on every app open.
- **Railway**: first request after Serverless sleep can return 502 (the client retries once); a deploy without root directory `backend` can't find the Dockerfile; `yt-dlp failed` in logs is YouTube blocking the datacenter IP (oEmbed fallback covers the title).
