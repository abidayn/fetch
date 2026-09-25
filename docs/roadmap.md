# Roadmap

What's still open, in priority order. Done work isn't tracked here — it's in
the git history.

---

## Now: security and housekeeping

- [ ] **Change the password of the production test account `rag-test@example.com`.**
      Its password was committed in the old `docs/plan.md` (public repo), and
      removing the file doesn't remove it from git history. Or delete the account.
- [ ] **Back up the release keystore** (`C:\Users\Acer\fetch-release.jks` + its
      password), then delete the unused `C:\Users\Acer\fetch-signing\` folder,
      which holds an old key and a plain-text password. See `operations.md` §4.
- [ ] **Finish converting old items to English summaries.** The free-tier quota
      (20 classifications/day) fits ~19 items a day; rerun the conversion until
      no Indonesian summaries remain (`backfill_enrichment.py --reclassify`
      re-does *all* items; prefer targeting only the remaining ones).

## Soon: unverified production checks

These were planned during deployment but never confirmed:

- [ ] Railway **Serverless** is enabled (otherwise the free credit drains 24/7).
- [ ] Cold-start behaviour after sleep: at most one 502, then success.
- [ ] The production `JWT_SECRET_KEY` is different from the laptop's `.env`.
- [ ] The old Supabase project (Sydney) is paused or deleted.
- [ ] End-to-end on the phone against production: share from YouTube, TikTok
      (video *and* photo post), Instagram, and a web page; cold-start share;
      search; "Summarise with AI"; open an item in its source app.

## Next: app quality

- [ ] **App name and ID.** The launcher shows the app as `mobile`
      (`android:label` in `AndroidManifest.xml`), and the package is still
      Flutter's placeholder `com.example.mobile`. Rename (e.g. label `Fetch`,
      ID `com.abidayn.fetch`). Changing the ID makes it a different app:
      testers uninstall the old one once.
- [ ] **Version name from the tag.** Pass `--build-name=${GITHUB_REF_NAME#v}` in
      the release workflow so Android shows e.g. `0.7.1` instead of `1.0.0`.
- [ ] **Faster AI answers.** `gemini-3.5-flash` takes 12–37 s per answer; a lite
      model measured ~5 s end-to-end, at the cost of slightly more confident
      wording. Needs its own per-model quota.
- [ ] **Recalibrate search thresholds** (`MIN_SCORE`, `MAX_GAP_FROM_TOP`) now
      that summaries are English and there's real usage data.
- [ ] **Backend tests.** There is no test suite; start with `extraction.py`
      (pure parsing, easy to fixture) and the search thresholds.
- [ ] Android developer verification / Play Protect recognition, only if the
      app is shared beyond personal use (needs the package rename first).

## Later: web client

Retrieval is often more convenient at a desk than on a phone (digging up a
tutorial while actually using it). Planned scope: **browse + search +
paste-a-link save** — not a full capture surface (browsers have no share sheet).

- **Same backend, same REST API.** The backend is already API-first; the only
  change is adding FastAPI's `CORSMiddleware` for the web origins.
- **React + Vite SPA**, React Router, native `fetch`. No SSR (an authenticated
  personal dashboard needs none).
- **Auth: JWT in `localStorage` with a short expiry.** Weighed against
  httpOnly cookies + CSRF protection; for a single-user tool the extra
  infrastructure isn't worth it against a low threat model. Revisit if Fetch
  stops being single-user.
- **Hosting:** Vercel or Netlify free tier.
- Tasks: CORS → scaffold → login/register → list view → search (with the same
  hybrid filters) → paste-a-link form (`POST /items`) → deploy.
- Non-goals: share-sheet equivalent, feature parity with mobile, SEO/public pages.

## Ideas (not planned)

- Keyword + vector fusion (e.g. Reciprocal Rank Fusion) for exact names and codes.
- Reranking the top ~50 vector results with a stronger model.
- An evaluation set of (query, expected item) pairs to measure recall@k
  whenever the model, thresholds or embedded text change.
- Use page body text beyond metadata for richer summaries.
- iOS build (Flutter makes it possible; needs a Mac to build and sign).
