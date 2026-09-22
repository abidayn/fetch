# Fetch — Post-MVP: Web Client

**This document is deliberately not merged into concept.md / plan.md /
knowledge-graph.md.** Those three stay scoped to the mobile-only MVP (Phase 0–6)
so the current build stays focused. This doc holds the nitty-gritty for the *next*
milestone — adding web access — worked out in advance so it's ready to fold in
once the MVP actually ships, instead of being designed from scratch later.

**When to start this**: after plan.md's Phase 4 (RAG search) is done. Web is a
browse/search/manual-save surface over endpoints that exist by that point — it
needs Phase 1 (auth + CRUD) and Phase 4 (search) finished, but not Phase 5/6
(mobile deployment/polish).

**How to fold this in when the time comes**: insert a new phase into plan.md
between the existing Phase 4 and Phase 5, renumbering Deployment → Phase 6 and
Polish → Phase 7; copy the concept nodes below into knowledge-graph.md; merge the
"Web client" and "Two clients, one backend" sections below into concept.md.

---

## Why web, and what it's for

The mobile app's share-sheet is the capture surface — that doesn't change. But the
*retrieval* half of the save → understand → retrieve loop is often more convenient
at a desk than on a phone: digging up a saved technical tip, a resume-writing
insight, or a tutorial while actually sitting down to use it. That's the pain point
driving this — not a desire for feature parity with mobile, but a genuinely
different use context for the same underlying data.

**Product scope decision**: web is **browse + search + manual-save**, not a full
capture surface.
- Browse/search existing saved items — same backend, same data, same hybrid RAG
  search as mobile.
- Manual "paste a link to save" form — calls the same `POST /items` endpoint the
  mobile share-sheet flow already uses. No new backend write-path.
- **No share-sheet equivalent.** Browsers don't have a mobile OS-level share
  target in any broadly-supported way; replicating that on web isn't worth
  chasing for a personal tool.

## Architecture: one backend, two clients

Mobile and web both talk to the **same FastAPI backend** over the **same REST
contract** — no mobile-specific or web-specific backend logic. This only works
cleanly because the backend was built API-first from the start, with no
assumptions baked in about the caller. The only backend change a browser client
actually requires is CORS (browsers enforce same-origin policy; mobile HTTP
clients don't — this never came up until now).

```
                    ┌─────────────┐
   share-sheet ───► │   Mobile     │
                    │  (Flutter)   │──┐
                    └─────────────┘  │
                                      ▼
                              ┌───────────────┐        ┌──────────────┐
                              │  FastAPI       │◄──────►│  PostgreSQL   │
                              │  backend       │        │  + pgvector   │
                              └───────────────┘        └──────────────┘
                                      ▲
                    ┌─────────────┐  │
  paste-a-link ───► │    Web       │──┘
  browse/search      │  (React)     │
                    └─────────────┘
```

No new business logic lives in either client beyond rendering and calling the
existing endpoints — the backend doesn't know or care which client is calling it.

## New tech stack

| Layer | Choice | Why |
|---|---|---|
| Web frontend | **React + Vite** | Plain SPA, not Next.js — an authenticated single-user dashboard doesn't need SSR/file-based routing/server actions; those solve problems this project doesn't have. Keeps the new surface area to "components, client-side routing, fetch," a clean contrast to Flutter's widget tree without importing a second framework's server model. |
| Client-side routing | React Router | Standard pairing with Vite; needed for login/home/search as separate views. |
| HTTP client | `fetch` (native) | No need for `axios`'s extra features at this scale; `fetch` is one less dependency and the same underlying concept already learned via mobile's `http-client-integration`. |
| Backend addition | `CORSMiddleware` (FastAPI built-in) | Only backend change required — allow the web app's origin(s). Not a new dependency, just new config. |
| Auth storage (web) | `localStorage`, short token expiry | Browser equivalent of mobile's bearer-token pattern. See tradeoff below. |
| Hosting | Vercel or Netlify (free tier) | Static SPA build; either is a trivial free deploy target for a Vite build. |

## Auth: JWT storage tradeoff (decided)

Two options were weighed:
- **`localStorage`** — simple, same bearer-token pattern as mobile. Vulnerable to
  XSS (any injected script can read it).
- **httpOnly cookie + CSRF protection** — more secure against XSS, but drags in
  CORS-with-credentials config, CSRF token handling, and cookie-specific backend
  logic.

**Decided: `localStorage`**, with short token expiry to bound the exposure window.
For a single-user personal tool, building CSRF infrastructure against a low threat
model wasn't judged worth the added complexity. Revisit this if Fetch ever stops
being single-user.

## Task breakdown (to insert as plan.md's new Phase 5 when this starts)

- [ ] Add CORS middleware to FastAPI, allowing the web app's dev/prod origins
      — concepts: cors-configuration
- [ ] Scaffold the React + Vite app, confirm it runs locally
      — concepts: web-app-structure
- [ ] Build login/register screens calling the backend's auth endpoints, store
      the JWT in `localStorage` — concepts: client-side-token-storage
- [ ] Build the home/list view fetching saved items from the backend
      — concepts: http-client-integration
- [ ] Build the search view hitting `/search` (same hybrid search as mobile)
      — concepts: http-client-integration
- [ ] Build a "paste a link to save" form calling the existing `POST /items`
      — concepts: http-client-integration
- [ ] Deploy the web client to Vercel or Netlify, pointed at the deployed API URL
      — concepts: deployment-hosting

`http-client-integration` gets tagged three times here — this is its first
re-encounter since mobile's Phase 2 task, which is exactly the "different task,
held up again" trigger for bumping it to `practicing` if it held up back then.

## New concept nodes (to copy into knowledge-graph.md when this starts)

```
## cors-configuration
- status: not-started
- depends-on: rest-api-design
- introduced: -
- last-reviewed: -
- evidence:

## web-app-structure
- status: not-started
- depends-on: none
- introduced: -
- last-reviewed: -
- evidence:

## client-side-token-storage
- status: not-started
- depends-on: jwt-auth, web-app-structure
- introduced: -
- last-reviewed: -
- evidence:
```

## Non-goals for this extension

- No share-sheet equivalent on web — capture stays mobile-only.
- No feature parity requirement beyond browse/search/manual-save — web doesn't
  need every mobile screen.
- No httpOnly-cookie/CSRF auth — explicitly deferred unless the single-user
  assumption changes.
- No SSR, no SEO work, no public-facing pages — this is an authenticated personal
  dashboard, not a public site.
