# Fetch — Project Description (source material for job applications)

This is a comprehensive reference document, not a resume or cover letter. It's meant
to be fed into an AI assistant along with a specific job posting, so it can pull out
and rephrase the relevant parts — a backend-focused role pulls different material
from this doc than a mobile-focused or AI/ML-focused one. Everything here is real:
the architecture, decisions, and rationale reflect what was actually designed and
built, not aspirational filler.

Scope covered: the app through its two core features — automatic organization and
RAG-based search — plus deployment to a live (if minimal) environment. Later
polish items (categories/browse UI, edit/delete, generative answers on top of
retrieval) are noted separately as explicitly out of scope for this version.

---

## Elevator pitch

Fetch is a full-stack mobile application that solves the "I saved something but can
never find it again" problem for short-form video content. Users share a link
directly from TikTok, Instagram, or YouTube into Fetch via the native Android
share-sheet; the backend automatically extracts whatever metadata is available,
uses Google's Gemini API to classify and summarize the content, and generates a
vector embedding for it — all without the user typing anything. Later, the user can
search their saved items using natural language ("that cooking video from a few
weeks ago") instead of exact keywords or manual tags, powered by a retrieval-
augmented generation (RAG) pipeline built on PostgreSQL with the pgvector extension.

## The problem and who it's for

People save content constantly across TikTok, Instagram Reels, and YouTube, almost
always with genuine intent to revisit it. The native "save" features on these
platforms are flat, unsearchable lists — content saved with good intentions
disappears into a pile the user never looks at again. This is especially acute for
someone who saves across multiple platforms and later has only a vague, non-keyword
memory of what they saved ("something about a workout routine, maybe a month ago")
with no way to search for that.

The target user is an individual, not a business or team — someone who already has
a habit of saving content and is mildly frustrated they never revisit it. This is a
solo, personal/learning project built with a near-zero operating budget, not a
funded product, which directly shaped several architecture decisions (see below).

## Core loop and differentiator

**Save → understand → retrieve.** Most save-for-later tools handle "save." Almost
none handle "understand" automatically — Fetch's differentiator is that the
organizing (title, summary, category) happens automatically at the moment of
saving, using AI to read whatever content is available, rather than relying on the
user to manually tag things later (which in practice never happens).

## Feature set

### 1. Share-intent capture (mobile entry point)
- Native Android share-sheet integration: the user shares a link from any app
  (TikTok, Instagram, YouTube, or a generic article/webpage) directly into Fetch,
  the same way they'd share to Messages or Gmail.
- No manual data entry, no copy-pasting URLs into a separate app.
- Implemented in Flutter using platform share-intent handling to receive the
  shared URL and forward it to the backend.

### 2. Automatic content organization (AI-driven understanding)
- On receiving a shared link, the backend runs a content-extraction step specific
  to the source: oEmbed APIs and Open Graph (`og:`) tags for generic/social
  content, richer metadata extraction (e.g. via yt-dlp) for YouTube where more
  data is exposed.
- Some platforms (TikTok, Instagram) expose very little data to unauthenticated
  requests by design — the system is built to degrade gracefully on thin metadata
  rather than fail, since this is an accepted platform constraint, not a bug.
- Whatever text/metadata is available gets sent to the Gemini API, which returns a
  structured title, a short summary, and a category classification.
- Deterministic code handles everything except the classification judgment call
  itself: fetching, parsing, storage, and routing are all non-AI; only "what is
  this content actually about" is delegated to the model. This boundary was a
  deliberate design decision — the AI is scoped narrowly to the one job that
  genuinely requires judgment.

### 3. RAG-based natural language search
- Every saved item gets a vector embedding (via a Gemini embedding model)
  generated from its AI-produced summary/content at save time, stored alongside
  the structured row in PostgreSQL using the `pgvector` extension.
- At query time, the user's natural-language search query is embedded the same
  way, and a cosine-similarity search against stored embeddings returns the
  semantically closest saved items — solving "I don't remember the exact title or
  wording, just roughly what it was about."
- Search supports **hybrid retrieval**: vector similarity is combined with
  structured filters over the relational columns — narrowing by content
  type/category (e.g. "videos" vs. "articles") and by a time range (e.g. items
  saved in the last two weeks) — rather than similarity search alone. This
  reflects a common real-world RAG pattern: pure embedding search is rarely
  sufficient on its own once queries have both a semantic component ("about
  cooking") and a structured component ("from last month").
- Stretch capability (explicitly optional, not required for feature-complete):
  feeding the top retrieved items back into Gemini to produce a single
  conversational answer, rather than returning a bare ranked list.

### 4. Authentication
- JWT-based auth (register/login), with middleware enforcing authenticated access
  to all item and search endpoints. Chosen over session/cookie auth because the
  client is a mobile app, not a browser — JWTs in an Authorization header are the
  natural fit for that client type.

### 5. Mobile app (Flutter)
- Cross-platform mobile client (Android-first, since Flutter also enables iOS
  later without a rewrite).
- Screens: authentication, home/list view of saved items, search.
- Talks to the backend exclusively over a REST API.

## Technical architecture

**High-level data flow:**

1. User shares a link from a source app → Android share-sheet → Fetch mobile app
   receives the intent.
2. Flutter app sends the URL to the backend via `POST /items` (authenticated).
3. Backend's extraction service fetches available metadata for that URL,
   branching by platform (oEmbed / `og:` tags / yt-dlp).
4. Extracted content is sent to Gemini, which returns structured
   title/summary/category.
5. Backend generates a vector embedding of the item's content via a Gemini
   embedding model.
6. Structured fields and the embedding are persisted together in PostgreSQL
   (`pgvector` column) in a single `saved_items` row tied to the authenticated
   user.
7. Later, the user issues a natural-language query from the search screen.
8. Backend embeds the query, runs a similarity search against stored embeddings
   in `pgvector`, applies any structured filters (category, time range) in the
   same query, and returns ranked results.
9. Flutter app renders the ranked results.

**Component breakdown:**

- **Mobile client** — Flutter (Dart), single codebase targeting Android
  (extensible to iOS). Handles UI, auth token storage, share-intent reception,
  and all HTTP communication with the backend.
- **Backend API** — Python, FastAPI. Chosen over a Node/Express alternative
  specifically because the AI/RAG portion of the system (Gemini SDK usage,
  embedding generation, vector-search query construction) has deeper, more
  mature tooling in the Python ecosystem, and there was no "shared language with
  the frontend" argument either way since the mobile client is Dart, not
  JavaScript. FastAPI specifically for built-in request/response validation via
  Pydantic and native async support, which matters here because both the AI
  calls and the content-extraction step are I/O-bound.
- **Database** — PostgreSQL with the `pgvector` extension. One database serving
  two roles: normal relational storage (users, saved items, structured metadata)
  and vector similarity search for RAG, rather than running a relational
  database and a separate dedicated vector database (e.g. Pinecone). This was a
  direct consequence of the near-zero budget constraint: one free-tier Postgres
  instance (Supabase or Neon, both ship with `pgvector`) covers both jobs.
- **AI provider** — Google Gemini API, used for exactly two jobs: (1) content
  classification/summarization from extracted text, and (2) generating vector
  embeddings for both stored items and incoming search queries.
- **ORM / migrations** — SQLAlchemy models with Alembic-managed migrations,
  versioning the schema (including the vector column) as it evolves.
- **Deployment** — backend deployed to a free-tier host (Railway, Singapore region, via Docker),
  secrets (Gemini API key, database credentials) managed via environment
  variables rather than being committed to source control. The mobile app is
  built and sideloaded directly to a device rather than published to the Play
  Store, since this is a personal tool rather than a distributed product —
  avoiding store fees and review overhead was an explicit, deliberate scope
  decision, not an oversight.

## Data model (core tables)

- **`users`** — account records backing JWT auth.
- **`saved_items`** — one row per saved link: source `url`, detected `platform`,
  AI-generated `title`, `summary`, `category`, raw extracted content, a vector
  `embedding` column (`pgvector`), and `created_at` (used both for display and as
  a structured filter in hybrid search).

## Key engineering decisions and rationale (useful for interview talking points)

- **Deterministic-vs-AI boundary drawn narrowly.** The temptation in an "AI app"
  is to let the model touch everything. Here, AI is scoped to exactly the two
  jobs that require judgment (classification, embeddings) — fetching, parsing,
  auth, storage, and routing are all deterministic code. This keeps the system
  debuggable and the AI's failure surface small and well-understood.
- **Single-database RAG architecture.** Using `pgvector` inside the primary
  relational database instead of a dedicated vector store trades some
  specialized vector-search performance for radically simpler infrastructure —
  one connection pool, one backup story, one free-tier account — appropriate for
  the project's actual scale and budget, and a deliberate example of not
  over-engineering for hypothetical future scale.
- **Hybrid retrieval over pure semantic search.** Recognizing early that a query
  like "workout videos from last week" has both a semantic component and a
  structured/filterable component, and designing the search endpoint to combine
  vector similarity with SQL-level filtering rather than relying on embeddings to
  encode everything (including time, which embeddings represent poorly).
- **Mobile-native entry point over a simpler web form.** A share-sheet-based save
  flow is significantly more implementation work than a paste-a-link web page,
  but it's the only entry point that matches how users actually discover and want
  to save this kind of content in the moment — a conscious tradeoff of build
  complexity for genuine UX fit.
- **Thin-metadata platforms treated as an accepted constraint, not a defect.**
  TikTok and Instagram intentionally expose little to unauthenticated scraping.
  The system is designed to degrade gracefully (shorter summaries, broader
  categories) rather than error out, since fighting platform anti-scraping
  measures was explicitly out of scope.
- **JWT over session auth**, driven by the client being a native mobile app
  rather than a browser.
- **Free-tier-only infrastructure** as a hard constraint throughout — every
  service choice (Supabase, Railway, Gemini's free tier) was
  evaluated against this from the start rather than retrofitted later.

## Skills and competencies demonstrated

- **Mobile development** — Flutter/Dart, native Android share-intent
  integration, HTTP client integration, app-side state management.
- **Backend/API development** — Python, FastAPI, REST API design, async I/O for
  external service calls.
- **Database engineering** — relational schema design, SQLAlchemy ORM,
  Alembic migrations, vector data types via `pgvector`, hybrid
  structured-plus-vector query design.
- **Authentication & security** — JWT-based auth, middleware-based route
  protection, environment-variable secrets management (no committed
  credentials).
- **AI/ML integration** — third-party LLM API integration (Gemini), prompt
  design for structured extraction (classification/summarization from
  unstructured text), embedding generation, and end-to-end RAG pipeline design
  (retrieval + optional generation).
- **Systems/architecture thinking** — deliberately scoping AI's role in a
  larger deterministic system, designing for a real budget constraint,
  recognizing when a "pure AI" solution (embeddings-only search) is
  insufficient and needs a structured/hybrid approach instead.
- **Content extraction / web scraping** — platform-specific metadata
  extraction (oEmbed, Open Graph tags, yt-dlp), handling inconsistent and
  sometimes minimal data across sources gracefully.
- **Product thinking** — identifying a genuine, personally-felt problem,
  scoping an MVP deliberately (explicit non-goals below), and shipping an
  end-to-end working system solo.
- **DevOps basics** — deploying a backend service to free-tier cloud hosting,
  managing environment-based configuration across local/production.

## Project context

Solo-built, first serious full-stack project, built as a learn-by-building
exercise rather than a funded or team effort — every architectural decision above
was made (and can be explained/defended) individually, not inherited from a
boilerplate or team convention.

---

*Update this doc once the project is actually complete through Phase 4 — replace
any forward-looking language with concrete specifics (actual challenges hit,
final decisions that changed from the original plan, real numbers if available
e.g. response latency, number of platforms supported).*
