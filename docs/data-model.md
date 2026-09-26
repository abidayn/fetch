# Data model

The source of truth for the table structure. The SQLAlchemy models
(`backend/models.py`) and the Alembic migrations follow this document, not the
other way round. The DDL is written as SQL for precision; the real
implementation goes through SQLAlchemy but must be equivalent.

Migrations so far: `9a2d76c47977` (both tables) → `66de89f6cd67` (HNSW index) →
`b3f1c2d4e5a6` (`classified_by`) → `c4d2e8f1a9b7` (`folders` + folder columns).

---

## Table `users`

```sql
CREATE TABLE users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT        NOT NULL UNIQUE,
    password_hash TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

| Column | Decision | Reason |
|---|---|---|
| `id` | `UUID`, not `BIGSERIAL` | IDs appear in API URLs (`GET /items/{id}`). Sequential integers can be guessed/enumerated and leak how much data exists. The cost: harder to read by hand while debugging. |
| `email` | `TEXT`, not `VARCHAR(255)` | In Postgres, `TEXT` and `VARCHAR` perform identically; `VARCHAR(n)` only adds a length check, and a made-up limit is a source of bugs (valid emails can be long). |
| `email` | `UNIQUE` | Email is the login identity. Duplicates would make login ambiguous. |
| `email` | stored **lowercase** (normalised in `routers/auth.py`) | `A@x.com` and `a@x.com` are the same person in practice, but different values to `UNIQUE`. |
| `password_hash` | `TEXT NOT NULL`, not `CHAR(60)` | Hash length depends on the algorithm; locking it would make changing algorithms a migration. The name itself documents that raw passwords never go here. |
| `created_at` | `TIMESTAMPTZ`, not `TIMESTAMP` | Stores an absolute point in time (UTC). Plain `TIMESTAMP` is ambiguous once the server runs in UTC and the user is in WIB. |

---

## Table `saved_items`

```sql
CREATE TABLE saved_items (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    url         TEXT        NOT NULL,
    platform    TEXT        NULL,

    title       TEXT        NULL,
    summary     TEXT        NULL,
    category    TEXT        NULL,
    raw_content TEXT        NULL,
    classified_by TEXT      NULL,

    folder_id         UUID  NULL REFERENCES folders(id) ON DELETE SET NULL,
    folder_by         TEXT  NULL,
    folder_suggestion TEXT  NULL,

    embedding   VECTOR(768) NULL,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_saved_items_user_id ON saved_items(user_id);
CREATE INDEX idx_saved_items_folder_id ON saved_items(folder_id);
CREATE INDEX idx_saved_items_embedding_hnsw ON saved_items
    USING hnsw (embedding vector_cosine_ops);
```

### What's `NOT NULL` and what may be `NULL` — the most important decision here

Only **three** columns must exist when the row is created: `id`, `user_id`,
`url`. Everything else may be empty, deliberately.

The `url` is the only thing we actually have the moment the user taps "share".
Every other column — `title`, `summary`, `category`, `raw_content`,
`embedding` — is an **enrichment** result that happens afterwards (scraping,
Gemini, embedding). Making them `NOT NULL` would mean **Gemini down = the user
can't save a link at all**, and saving is the core of the product. With nullable
columns:

1. Save the row with just the `url` → the user gets an immediate confirmation.
2. Enrichment runs afterwards (in a background task; it can fail and be retried).

### NULL = work queue

The empty columns double as work queues, so there's no status/flag column:

- needs (re)classification → `summary IS NULL`
- needs an embedding → `embedding IS NULL` (`backfill_embeddings.py`)

### `raw_content` encodes the enrichment state

| `raw_content` | Meaning | API |
|---|---|---|
| `NULL` | Not processed yet (just saved, or the server died mid-task) | `processed: false` |
| `''` (empty string) | Processed, but nothing could be extracted (private/deleted post, 404) | `processed: true`, `has_content: false` |
| text | Processed, holds the extracted text | `processed: true`, `has_content: true` |

`processed` and `has_content` are properties on the model, not columns. They let
the app show "processing" only for items that are really queued, and tell
"couldn't read this link" apart from "the AI failed on readable content"
(`processed`, `has_content`, `summary IS NULL`).

`backfill_enrichment.py` re-processes `raw_content IS NULL` and
`summary IS NULL AND raw_content != ''`, and deliberately skips `''`.

### Per column

| Column | Decision | Reason |
|---|---|---|
| `user_id` | `NOT NULL` + foreign key | An item without an owner means nothing here. The FK guarantees no item points at a missing user. |
| `ON DELETE CASCADE` | deleting a user deletes their items | Alternatives are `RESTRICT` or `SET NULL` (orphaned items). For a personal app, deleting an account means deleting its data. |
| `url` | `NOT NULL` | The only data guaranteed at save time. |
| `platform` | `NULL` | Set by extraction: `youtube` / `tiktok` / `instagram` / `generic`. |
| `title` | `NULL` | Set by Gemini (or the extracted title if Gemini fails). Editable by the user. |
| `summary`, `category` | `NULL` | Pure Gemini output, in English. `category` is always one of the fixed list in `classifier.py`. Editable by the user. |
| `raw_content` | `NULL` | The raw extracted text (max 4000 chars), **kept on purpose** even after `summary` exists: if the prompt or model changes, items can be re-classified from it **without re-scraping** (`backfill_enrichment.py --reclassify`) — and scraping is fragile (pages change, get rate-limited, get deleted). Cheap insurance. |
| `classified_by` | `NULL` | Who wrote the current title/summary/category: a model id like `gemini:gemini-3.6-flash` or `groq:openai/gpt-oss-120b`, or `user` after an edit in the app. `NULL` = unknown (items from before this column) or never classified. Items not written by the primary classifier model and not by `user` are re-classified by the primary later (`enrichment.upgrade_fallback_items`), so a fallback model's weaker summary is temporary and user edits are never overwritten. |
| `folder_id` | `NULL`, FK `ON DELETE SET NULL` | The user's folder for this item. `NULL` = Unfiled, which is also what saving without choosing a folder leaves. Deleting a folder un-files its items instead of deleting them: a folder is just a grouping, the links are the data. |
| `folder_by` | `NULL` | Who decides the folder: `user` (picked in the app, never changed by the AI), `ai` (the user tapped "Let AI pick"), or `NULL` (nobody asked for a folder). `ai` with `folder_id` still `NULL` means "the AI hasn't placed it yet": the user can ask before enrichment has finished, and enrichment (or a later re-classification) places it then. Once placed, the AI never moves it again. See "Folders: who decides" below. |
| `folder_suggestion` | `NULL` | The folder name the classifier proposed, written in the same Gemini call as title/summary/category (no extra quota). Either the name of one of the user's folders or a new short name when none fits. Stored as text, not as a folder id: it only becomes a real folder when the user taps "Let AI pick", so nothing is created behind the user's back, and a folder the user creates later under the same name still matches. |
| `embedding` | `VECTOR(768) NULL` | See below. |
| index on `folder_id` | added | Browsing by folder and counting items per folder. |
| `created_at` | `NOT NULL DEFAULT now()` | Display order, and the time-range filter in hybrid search. |
| index on `user_id` | added | The most frequent query is "all items of user X". Postgres does **not** index foreign keys automatically. |
| HNSW index on `embedding` | `vector_cosine_ops` | Approximate nearest-neighbour search. The operator class must match the query operator (`<=>`); see "Gotchas" in `CLAUDE.md`. |

---

## Table `folders`

```sql
CREATE TABLE folders (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_folders_user_name ON folders (user_id, lower(name));
```

Folders are the user's own grouping of their items, next to `category` (the
AI's fixed taxonomy, kept for search filters). The user creates them, or the
AI proposes one when the user asks it to pick.

| Column | Decision | Reason |
|---|---|---|
| `user_id` | `NOT NULL` + FK `ON DELETE CASCADE` | Same ownership model as `saved_items`. Another user's folder is a 404, like another user's item. |
| `name` | `TEXT`, trimmed, whitespace collapsed, 1–40 chars (enforced in `folders.py`) | Short enough to fit a chip. Kept in the user's own spelling and case. |
| unique on `(user_id, lower(name))` | case-insensitive | "Recipes" and "recipes" are the same folder to a person. It also lets the AI's suggestion be matched to an existing folder by name, and makes two simultaneous creations of the same name end in one folder instead of two. |
| no `item_count` column | computed with a `COUNT` join | Derivable data isn't stored (same rule as `updated_at` below). |
| max 50 folders per user | enforced in `folders.py` | The folder names go into every classification prompt; an unbounded list would grow every prompt. |

### Folders: who decides

- **The user picks a folder** → `folder_id` = it, `folder_by = 'user'`. The AI never touches it.
- **The user taps "Let AI pick"** → `folder_by = 'ai'`. If enrichment has
  finished, `folder_suggestion` is applied right away: matched to an existing
  folder by name (case-insensitive), or created as a new folder. If
  enrichment hasn't finished, it's applied when it does. Both paths lock the
  item row (`SELECT … FOR UPDATE`) before deciding, so a tap that lands at
  the same moment enrichment finishes can't be lost.
- **Nobody picks** → both stay `NULL`: the item is Unfiled.
- **Folder deleted** → its items get `folder_id = NULL` and `folder_by = NULL`
  (Unfiled), so the AI doesn't re-file them into a re-created folder.

---

## Relationships

```
users (1) ──────< (many) saved_items >────── (0..1) folders
        id              user_id   folder_id          id
users (1) ──────< (many) folders
```

A plain one-to-many relationship via the FK on the "many" side. Fetch is
effectively single-user, but `users` existed from the start: JWT auth needs an
owner for each token, and adding ownership after data exists is far more
expensive than setting it up first.

---

## Embedding dimension: **768**

This can't be changed easily, so the reasoning is written out in full.

**The constraints:**
- `gemini-embedding-2` produces **3072** dimensions by default, and supports
  truncation to **1536** or **768** via `output_dimensionality`.
- pgvector indexes (HNSW and IVFFlat) **only support up to 2000 dimensions.**
  At 3072 the column couldn't be indexed at all.

**Why 768 rather than 1536:**
- What gets embedded is a short title + summary, not a long document. The
  quality difference between 768 and 3072 is small for this.
- 4× less storage: ≈ 3 KB per item instead of ≈ 12 KB. Relevant on a 0.5 GB
  free-tier database.
- Faster queries: shorter vectors to compare.

**What breaks if the embedding model changes:**

1. Changing the dimension needs a **schema migration**, not just a config change.
2. All existing embeddings must be **regenerated** (`backfill_embeddings.py --all`).
   Vectors from different models live in different "spaces" — comparing them
   produces numbers that are mathematically valid but **meaningless**. A silent
   failure: no error, search results just become nonsense.
3. This holds even if the dimension happens to be the same. Same length ≠ comparable.
4. The relevance thresholds in `routers/search.py` are calibrated for this model
   and must be recalibrated too (see `docs/decisions.md`).

---

## Decisions deliberately deferred

| Item | Status | Reason |
|---|---|---|
| `UNIQUE (user_id, url)` | **not used** | Would prevent duplicate saves, but forces `POST /items` to handle conflicts and blocks users who deliberately save again. Revisit if duplicates become a real annoyance. |
| `updated_at` / `enriched_at` | **not used** | The information can be derived from `summary IS NULL` / `embedding IS NULL`. Don't add columns whose content can be computed from other columns. |
| Separate `categories` table | **not used** | `category` as TEXT from a fixed list is enough. A table only makes sense if categories need their own attributes (colour, icon, order). |
