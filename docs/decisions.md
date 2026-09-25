# Decisions

Why Fetch is built the way it is. Each entry: the decision, the reason, and
what would make us revisit it. Schema decisions live in `data-model.md`.

---

## Product scope

- **One job: save → understand → retrieve.** Links are captured from the
  Android share sheet with zero typing; AI fills in title, summary and
  category; later the user finds items by meaning ("that pasta video from last
  month"), not by exact words or manual tags.
- **Personal tool, not a platform.** Built for one person (multi-account
  capable, but no teams, sharing, or social features). This justifies several
  simplifications below (single worker, free tiers, sideloaded APK).
- **Non-goals:** a web client (planned, see `roadmap.md`), team/SaaS features,
  a social feed, fighting platform anti-scraping (thin data from TikTok and
  Instagram is accepted), and search-relevance tuning as a science project.
- **AI is scoped narrowly.** Deterministic code does fetching, parsing, auth,
  storage and routing. The model only does the parts that need judgement:
  classification/summarising, embeddings, and the optional narrative answer.
  This keeps the system debuggable and the AI failure surface small.
- **English everywhere (2026-09-25).** UI, API messages, AI summaries and
  answers are English. Titles keep the content's original language (a title is
  a name, not UI text).

## Architecture

| Decision | Why |
|---|---|
| **FastAPI (Python)** backend | The AI/RAG tooling (Gemini SDK, pgvector, scraping, yt-dlp) is most mature in Python; Pydantic gives request/response validation for free. |
| **One Postgres with pgvector** for both relational data and vectors | One free-tier database, one connection pool, one backup story — instead of Postgres + a separate vector DB (e.g. Pinecone). Appropriate for the real scale. |
| **Flutter**, Android-first | The share-sheet capture is the core UX and needs a native app; Flutter keeps iOS possible later without a rewrite. |
| **JWT bearer tokens**, not sessions | The client is a native app, not a browser; tokens in an `Authorization` header are the natural fit. 7-day expiry. |
| **Save first, enrich in the background** | `POST /items` stores only the URL and returns 201 immediately; extraction + Gemini (4–9 s, can fail) run as a `BackgroundTask`. Saving must never wait for, or fail because of, scraping or AI. |
| **Single uvicorn worker** | Limited free-tier Supavisor connection pool, and `BackgroundTasks` run in-process. Revisit if traffic ever needs more. |
| **`POST /search`**, not `GET` | A search query is personal data; in a `GET` it would end up in URLs and server/proxy logs. |
| **404 (not 403)** for other users' items | A 403 would confirm that the item exists. |
| **Fixed category list** (`classifier.py`) | Free-text categories from the model ("Cooking" vs "Food & Recipes") would split one topic into many labels and break browsing/filtering. Served to the app via `GET /items/categories` so there's one source of truth. |
| **No state-management library** in Flutter | The only cross-widget need is "refresh home when a share arrives"; a `GlobalKey` covers it. |
| **Tokens in flutter_secure_storage** | Android Keystore-backed; SharedPreferences is plain XML readable on rooted devices / via adb backup. |

## Hosting and infrastructure (free tier only)

Free tiers are a hard constraint; every service was chosen against it.

| Decision | Why / history |
|---|---|
| **Backend on Railway**, Singapore region, via `backend/Dockerfile` | Originally planned for Render (2026-09-21), but Render required a credit card at sign-up. Railway has a Singapore region and a no-card trial ($5/30 days) then a Free plan ($1 credit/month). Running 24/7 would cost ≈ $3/month, so **Serverless** (sleep after ~5 min idle) must be on. Trade-off: the first request after sleep can return one 502 — the app retries once for that. |
| **Database: Supabase, Singapore** (`ap-southeast-1`) | Moved from Sydney (2026-09-22) before launch, while it held only test data. Server-in-Singapore ↔ DB-in-Sydney cost ≈ 90–100 ms on *every* query, including plain saves and list loads — not worth paying forever. |
| **Supavisor session pooler** in `DATABASE_URL`, not the direct connection | Supabase's direct host is IPv6-only; the pooler works over IPv4 from any host (verified from Railway). |
| **Dev and production share one database** | Simplicity for a single-user project. Consequence: a local backend or backfill script reads and writes **production data**, and the Gemini quota is shared between laptop and server. |
| Free-tier sleep behaviour | Railway sleeps after ~5 min idle; the Supabase project **pauses after 1 week** unused. After a week away, expect two wake-ups. |
| **APK via GitHub Releases**, not the Play Store | Personal tool: no store fees or review. A tag push builds a signed APK (`docs/operations.md`). The app is signed with our own key, so Play Protect warns on first install. |

## Content extraction

The contract: `extract(url)` never raises; failures produce thinner data, not
failed items. Per platform (see `backend/extraction.py`):

| Platform | Chain | Why |
|---|---|---|
| YouTube | yt-dlp → YouTube oEmbed → Open Graph | yt-dlp gives the full description but YouTube blocks it from datacenter IPs (Railway); oEmbed is a public embed API that still returns the real title + channel. |
| TikTok | oEmbed → `/embed/v2/<id>` page JSON → Open Graph | oEmbed only serves videos (photo/slideshow posts get a misleading "429 ratelimit"); the embed page carries the caption for both. Short `vt.tiktok.com` links are resolved first to get the ID. |
| Instagram | Open Graph fetched as `facebookexternalhit` | Instagram serves logged-out browsers an empty JS shell but link-preview crawlers the full caption. IG oEmbed needs a Facebook app token. |
| Generic | Open Graph, then the first long paragraphs | Many articles (e.g. Wikipedia) have no meta description. |

Generic platform text ("- YouTube", "Enjoy the videos and music you love…",
"TikTok - Make Your Day") is filtered as junk, so Gemini is never asked to
summarise the platform itself. With no content at all, Gemini isn't called
(it could only hallucinate from the URL).

## Embeddings and search

**Model: `gemini-embedding-2` at 768 dimensions**, chosen over
`gemini-embedding-001` after testing 3 documents × 3 queries:

| Model | Avg. score gap, right vs best wrong doc | Vectors normalised? |
|---|---|---|
| `gemini-embedding-001` | ≈ 0.13 | No (length ≈ 0.59) |
| `gemini-embedding-2` | ≈ 0.16 | Yes (length = 1.0) |

A wider gap = more decisive. `task_type` makes no difference on this model, so
items and queries use the same (symmetric) embedding function.

**What gets embedded: `title + "\n" + summary`.** On 8 items × 8 queries, all
variants put the target at rank 1 (summary only: gap +0.130; title + summary:
+0.128; + raw_content: +0.138) — a tie, so the choice is by reasoning: the
title keeps proper names in their original language ("Despacito",
"Carbonara"); raw_content is excluded because YouTube descriptions are full of
sponsor links and calls to subscribe that dilute the meaning. Since items are
short AI summaries with a single topic, no chunking is needed.

**Distance: cosine (`<=>`).** On normalised vectors, cosine, L2 and inner
product rank identically (L2² = 2 × cosine distance); cosine stays correct if a
future model isn't normalised, and gives an easy 0–1 score. The HNSW index uses
`vector_cosine_ops` to match.

**HNSW index** (benchmark on a temporary 10,000-vector table of clustered,
realistic data): exact scan 80.9 ms → HNSW 1.4 ms (≈ 57× faster) at 98%
recall@10 with the default `ef_search = 40`. On uniformly random data recall
drops to 32% — HNSW relies on real embeddings having topical structure. With
few rows the planner correctly still chooses a sequential scan.
`SET LOCAL hnsw.iterative_scan = strict_order` makes filtered searches (by
`user_id`, category, date) keep searching until enough rows pass the filter.

**Relevance thresholds** (`routers/search.py`), calibrated on ~20 items
(queries as actually tested, several in Indonesian):

| Query | Result | Score | Relevant? |
|---|---|---|---|
| "rendang" | Rendang | 0.807 | ✓ |
| "workout" | HIIT | 0.718 | ✓ |
| "cara biar investasi berkembang" (how to grow investments) | Compound interest | 0.596 | ✓ (2nd result) |
| "workout" | Pomodoro Technique | 0.607 | ✗ |
| "asdfghjkl" | Nasi goreng | 0.609 | ✗ (random text) |
| "harga tiket pesawat ke jepang" (flight prices to Japan) | Mount Bromo | 0.490 | ✗ |

These were measured when summaries were Indonesian. Summaries are English now
(the embedding model is multilingual), so re-check these thresholds against
real searches.

Scores are not percentages: every item has a baseline similarity of ~0.5, and
short or random queries raise *all* scores. So two filters are needed:
`MIN_SCORE = 0.60` (drops queries with no answer) and
`MAX_GAP_FROM_TOP = 0.06` (drops the irrelevant tail when the baseline is
high). The thresholds are deliberately loose — missing a saved item is worse
than showing one extra. Known cost: some true matches just under 0.60 are
dropped, and random text can still return something. **Recalibrate** whenever
the embedding model changes or with real usage data.

**Hybrid retrieval.** Category and date filters go into the same SQL `WHERE`
as the vector distance — never filtered in Python after the `LIMIT`, which
could leave zero results even when matches exist further down. Dates can't be
"understood" by embeddings, so they must be columns.

## Generated answers (`POST /search/answer`)

| Decision | Why |
|---|---|
| **Separate models** from classification (the two chains share no model) | Free-tier quota is per model, and the classifier model only gets 20 requests/day (+5/min). Sharing one would let answers starve new-item classification. |
| **Top 5 items as context** | More tokens = slower and costlier, and marginally relevant items tempt the model into forced connections. |
| **No retrieval results → Gemini isn't called** | With empty context the model answers from general knowledge — exactly the hallucination RAG is meant to prevent. |
| **Grounding + `[n]` citations**, invalid numbers stripped | The UI highlights sources by number; a fake number misleads more than none. |
| **Prompt-injection defence** | Item text is written by strangers (scraped pages). It's wrapped in `<item>` tags and declared as data; the answer is display-only text that never triggers actions. Tested with a planted "IGNORE ALL PREVIOUS INSTRUCTIONS" item: the model answered normally. This reduces, not eliminates, the risk. |
| **Answer on request** (button), not on every search | Each answer is a Gemini call against a small daily quota, and the result list is often enough. |

Known limitation: `gemini-3.5-flash` answers take 12–37 s; with the 25 s
budget, slow answers now come from the fast fallback model instead (see below).

## AI fallback (2026-09-25)

Research (September 2026) across OpenRouter, LiteLLM, Portkey, pydantic-ai and
engineers' post-mortems; the parts that shaped `backend/llm.py`:

| Decision | Why |
|---|---|
| **Chains:** Classify `gemini-3.6-flash` → `gemini-3.5-flash-lite` → Groq `openai/gpt-oss-120b`; Answer `gemini-3.5-flash` → `gemini-3.1-flash-lite` → Groq `openai/gpt-oss-20b` | Gemini quotas are per project **and per model**, so a second Gemini model is the cheapest fallback (no new key, SDK or data recipient). Groq is last: free, OpenAI-compatible, strict JSON-schema output only on its `gpt-oss` models. The two chains share no model. Configurable via `CLASSIFY_MODELS` / `ANSWER_MODELS` because free-tier catalogues change without notice (Groq's free Llama 70B disappeared before we started). |
| **Classify errors by cause, not status code** | The most common router bug: treating every 429 alike, so a daily quota gets retried every minute all day ([dev.to](https://dev.to/eleata/how-multi-provider-llm-routers-silently-fail-5fdd), [ellmer #1154](https://github.com/tidyverse/ellmer/issues/1154)). Gemini's daily-quota 429 carried `retryDelay: 11s` in our own logs, so the retry delay can't detect it — `quotaId` (`…PerDay…`) can. |
| **Per-model state in memory** (rate-limited until / exhausted until midnight Pacific / unhealthy after 3 failures / unusable) | A small circuit breaker: known-dead models are skipped without a call. In-memory is enough with one worker; a restart just rediscovers state. |
| **Retries in one place** (SDK retries off for generation) | Client retries under a fallback layer multiply attempts and delay ([pydantic-ai #3267](https://github.com/pydantic/pydantic-ai/issues/3267)). |
| **One time budget per action + hard per-attempt deadline** | Fallback must not make a slow path slower. The answer budget (25 s) sits under the app's 30 s timeout; a live test showed an HTTP timeout isn't a call deadline (43.5 s against 30 s). Timed-out models aren't retried on the same request — a live test showed that retry eating the whole budget. |
| **Validate every response** (same Pydantic schema for all providers) | "200 OK" with empty content or schema-violating JSON is common across providers ([Pinggy](https://pinggy.io/blog/openrouter_production_provider_routing_pitfalls/), [Requesty: 82% of 244 models pass](https://www.requesty.ai/blog/structured-outputs-across-llm-providers-the-compatibility-mess)); it counts as a failure. |
| **Record who answered** (`classified_by`) + **upgrade job** | Every serious gateway reports the serving model. Because `raw_content` is kept, fallback summaries (and failed classifications) are redone by the primary within its spare quota — a fallback lowers quality only temporarily. Triggered by `GET /items`, not a timer, because the server sleeps when idle. |
| **No gateway library** | LiteLLM/Portkey solve this at a scale we don't have, and a gateway holds every API key: LiteLLM 1.82.7/1.82.8 on PyPI shipped a credential stealer ([incident report](https://docs.litellm.ai/blog/security-update-march-2026)). Groq is called with the existing `httpx` — zero new runtime dependencies. |
| **No embedding fallback** | Vectors from different models live in different spaces; a real-world fallback silently corrupted search ([openclaw #96534](https://github.com/openclaw/openclaw/issues/96534)). The search fallback will be keyword search instead (roadmap). |
| **Privacy accepted:** content may reach Groq | Only after both Gemini models fail. Gemini's free tier itself may use content for training (outside the EU/UK). |
