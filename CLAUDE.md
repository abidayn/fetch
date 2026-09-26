# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Every time you execute a task, end the message with a recap.**

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
venv/Scripts/python.exe backfill_enrichment.py --reclassify  # re-run classification on stored raw_content (after prompt/model changes)
venv/Scripts/python.exe backfill_embeddings.py [--all]       # fill NULL embeddings; --all after changing embedding model
venv/Scripts/python.exe -m pip install -r requirements-dev.txt  # + pytest (dev only)
venv/Scripts/python.exe -m pytest                            # all tests (tests/, no network)
venv/Scripts/python.exe -m pytest tests/test_llm.py -k quota  # a subset
venv/Scripts/python.exe -m alembic check                     # models.py matches the database?
```

Requires `backend/.env` (copy `.env.example`): `GEMINI_API_KEY`, `DATABASE_URL` (plain `postgresql://` — `database.py` rewrites it to the `psycopg` v3 driver), `JWT_SECRET_KEY`; optional `GROQ_API_KEY` (last-resort fallback) and `CLASSIFY_MODELS` / `ANSWER_MODELS` (chain overrides). `check_db.py` / `check_gemini.py` are throwaway connectivity checks. Tests cover the fallback layer (`tests/test_llm.py`) and the folder logic (`tests/test_folders.py`); neither touches the network or the database.

**Dev and production share one Supabase database.** A local server and every backfill script read and write production data, and the Gemini free-tier quota (classifier model: 20 requests/day, 5/min) is shared with the server.

Deployed on **Railway** (Singapore; not Render) via `backend/Dockerfile`, Railway root directory `backend`, single uvicorn worker (limited Supavisor pool; BackgroundTasks run in-process). Production URL: `https://fetch-production-35a4.up.railway.app` (baked into the APK via `API_BASE_URL`). Merging to `main` does not by itself prove production is updated — verify routes with `/openapi.json`. Migrations are not run on deploy; run them from the laptop. Details: `docs/operations.md`.

### Mobile (`mobile/`, Flutter SDK at `C:\flutter`, may not be on PATH)

```bash
flutter pub get
flutter run                                                   # talks to local backend
flutter run --dart-define=API_BASE_URL=https://<backend>      # talks to a deployed backend
flutter analyze
flutter test                                                  # smoke test + folder picker widget tests
flutter test test/folder_picker_test.dart
```

Without `API_BASE_URL`, `ApiClient` uses `http://10.0.2.2:8000` on Android (emulator alias for host localhost) and `127.0.0.1:8000` elsewhere; a physical device needs the define.

### Release

`.github/workflows/android-release.yml` builds a signed release APK on `v*` tags and attaches it to a GitHub Release. Signing uses `android/app/release.jks`, which only exists in CI (decoded from secrets); local release builds fall back to the debug key (`mobile/android/app/build.gradle.kts`). Build number comes from `github.run_number` so each APK can upgrade the previous one. Keystore and secrets: `docs/operations.md` §4.

## Backend architecture

- `main.py` wires four routers: `routers/auth.py` (register/login, JWT via `security.py`), `routers/items.py` (CRUD + `PUT /items/{id}/folder`), `routers/folders.py` (folder CRUD with item counts), `routers/search.py` (`POST /search`, `POST /search/answer`). Auth is `deps.get_current_user` (Bearer JWT → `User`; every failure is the same 401).
- **Save flow**: `POST /items` stores only the URL and returns 201 immediately, then schedules `enrichment.enrich_item` as a BackgroundTask (with its own DB session). Enrichment = `extraction.extract` (per-platform fallback chains: YouTube yt-dlp → YouTube oEmbed → OG, since YouTube blocks yt-dlp from Railway's datacenter IPs; TikTok oEmbed → `/embed/v2/<id>` page JSON, which also covers photo posts; Instagram OG fetched with the `facebookexternalhit` crawler UA, since normal browsers get an empty JS shell; generic OG. Generic platform titles/descriptions are filtered as junk so Gemini never summarises the platform itself) → `classifier.classify` (Gemini structured output: title, English summary, category) → `embeddings.embed_one` on title+summary.
- **"Never raise" contract**: `extract`, `classify`, `embed*`, and `generate_answer` return thin data or `None` on failure instead of raising. Callers decide what that means (keep NULL for backfill, or return 503 on search). Preserve this when touching them.
- **Processing state is encoded in `raw_content`**, no status column: `NULL` = not yet processed, `""` = processed but nothing extractable, otherwise extracted text. `SavedItem.processed` and `SavedItem.has_content` (lets the app tell "link unreadable" from "AI failed") derive from this; `PATCH /items/{id}` returns 409 while unprocessed (enrichment would overwrite edits). NULL `embedding`/`summary` act as work queues for the backfill scripts.
- **Categories** are a fixed `Literal` in `classifier.py` and served to the app via `GET /items/categories` — that is the single source of truth (no copy in Flutter). `/categories` must stay registered before `/{item_id}`.
- **Editing** title/summary re-embeds the item; a failed re-embed keeps the old vector.
- **Folders** (`folders.py`; rules in `docs/data-model.md` "Folders: who decides"): user-owned, next to categories. The classification call also returns `folder` (an existing name or a proposed new one), stored as the text `folder_suggestion` — no extra AI call, and nothing is created until the user taps "Let AI pick". `folder_by` = `user` | `ai` | NULL; `ai` + NULL `folder_id` = waiting for the AI. `folders.apply_ai_folder` turns the suggestion into a folder (case-insensitive match, else create; max 50) and must run with the item row locked: `PUT /items/{id}/folder` locks it, and every enrichment/upgrade write re-reads it via `enrichment.lock_item` (`refresh(with_for_update=True)`) — keep slow network calls (classify, embed) *before* that lock. The AI never moves a placed item or touches `folder_by='user'`; deleting a folder also clears `folder_by`, or the upgrade job would re-create it. A folder choice doesn't set `classified_by='user'`.
- **Search** (`routers/search.py::retrieve`): cosine distance on pgvector HNSW with filters (category, folder, created_at range) in the same SQL WHERE, `SET LOCAL hnsw.iterative_scan`, and two relevance cutoffs (`MIN_SCORE`, `MAX_GAP_FROM_TOP`) calibrated for `gemini-embedding-2` (evidence in `docs/decisions.md`) — recalibrate if the embedding model changes. `/search/answer` skips Gemini entirely when retrieval returns nothing.
- **AI fallback (`llm.py`)**: every *generation* call (classify, answer) goes through `llm.generate_json` / `llm.generate_text`, which walk an ordered chain (`classifier.CHAIN`, `answerer.CHAIN`: primary Gemini → second Gemini → Groq) — never call `get_client().models.generate_content` directly. It classifies each failure by cause (daily quota via Gemini's `quotaId`, per-minute limit, overload/timeout, bad request, model gone, invalid output), keeps per-model state in memory (single worker), enforces one time budget per action with a hard per-attempt deadline, and returns the value plus the model that produced it. Classifier and answer chains use disjoint models because free-tier quota is per model. The answer budget (25 s, 15 s per attempt) must stay under the app's 30 s timeout, or the app retries the whole request; classification runs in the background and gets 60 s.
- **Provenance + upgrade**: `saved_items.classified_by` records which model (or `user`) wrote an item's title/summary/category. `enrichment.upgrade_fallback_items` (triggered by `GET /items`, throttled to every 15 min, 3 items per run, primary model only, stops on quota) re-classifies items not written by the primary or the user — upgrading fallback results and retrying failed classifications. Any edit via `PATCH /items/{id}` sets `user`, so edits are never overwritten.
- **Gemini client**: one lazy client in `gemini.py` (so Alembic can import models without the API key). Its SDK retries apply to embeddings only; `llm.py` disables them per call so retries happen in one place. **Embeddings never fall back** to another model (vectors from different models aren't comparable): model/dimension (`embeddings.py`) must match `Vector(768)` in `models.py`; changing either requires a migration plus `backfill_embeddings.py --all`.
- Ownership: other users' items return 404, not 403.

## Mobile architecture

- `lib/api/api_client.dart` is the only place that does HTTP; it attaches the token from `token_storage.dart` (flutter_secure_storage), applies a 30s timeout, and retries once on transient failures (network, 502/503/504) — but **never retries `POST /items`** (could double-save) or register. Errors surface as `ApiException` (`statusCode` 0 = offline/timeout); backend `detail` messages are shown to the user as-is.
- **Waiting for enrichment is client-side polling** (no push): `save_result_sheet.dart` re-fetches the item every 3 s until `processed` — and, after "Let AI pick", until the AI has placed it (gives up after 60 s) — and `home_screen.dart` reloads the list every 4 s while any item is unprocessed, capped at 10 polls. Each list reload is a `GET /items`, which is also what triggers the throttled upgrade pass — keep that throttle if you change polling.
- `lib/main.dart` listens for shared links via `receive_sharing_intent` for both warm (stream) and cold-start (`getInitialMedia`) shares, and uses global Navigator/ScaffoldMessenger/HomeScreen keys to show the save sheet and refresh from outside the widget tree. No state-management library.
- **Folder picker** (`widgets/folder_picker.dart`) is stateless; `save_result_sheet.dart` owns the item and sends choices optimistically, dropping replies/polls from an older choice (`_version`). The same sheet serves the tile's "Move to folder" (`showFolderSheet`). Home browses by folder; counts come from the loaded items, names from `GET /folders`. Folder *search* is client-side (`filterFolders` in `models/folder.dart`): the search screen lists matching folders per keystroke and pops with the tapped folder's id for home to open; the picker's "Find a folder" box appears above `kFolderSearchThreshold` (6) folders.
- Screens in `lib/screens/`, bottom sheets and tiles in `lib/widgets/`.

## Gotchas (each one bit us before)

- **Alembic autogenerate diffs against the database's current state**, not the intended history. A dirty database produced a migration that dropped a stray table and failed on fresh installs. Always read generated migrations before applying.
- **Embeddings: pass each text as its own `types.Content`.** A plain `list[str]` makes `gemini-embedding-2` return one combined vector, silently. `embed()` also checks vector count and length.
- **HNSW operator class must match the query operator** (`vector_cosine_ops` ↔ `<=>`); ordering by `<->` silently falls back to a sequential scan. With few rows the planner uses a seq scan anyway — that's correct.
- **Android splash freeze on cold-start share**: Flutter's implicit splash dismissal doesn't fire when the Activity is launched via the share-sheet trampoline. Fixed with `androidx.core:core-splashscreen` + `installSplashScreen()` in `MainActivity.kt` + `LaunchTheme` extending `Theme.SplashScreen` — don't remove any of the three.
- **`INTERNET` permission must be in the main `AndroidManifest.xml`** — the debug manifest has it, so debug builds work while release builds can't reach the network.
- **Share intent**: `launchMode="singleTask"`, and `ReceiveSharingIntent.instance.reset()` after handling, or the same share is re-read on every app open.
- **Gemini's daily-quota 429 says "retry in ~11s"** even though the quota resets at midnight Pacific. Only the `quotaId` (`...PerDay...`) tells daily from per-minute limits — never infer it from the retry delay.
- **HTTP timeouts aren't call deadlines**: they apply per connection phase, so a stalling server held a call for 43.5 s against a 30 s timeout. `llm.py` enforces a hard deadline per attempt, and never retries a timed-out model on the same request.
- **Railway**: first request after Serverless sleep can return 502 (the client retries once); a deploy without root directory `backend` can't find the Dockerfile; `yt-dlp failed` in logs is YouTube blocking the datacenter IP (oEmbed fallback covers the title).
