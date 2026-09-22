# Project Instructions

This is a learn-while-building project. I'm an IS student, not CS, not a
total beginner. Skip fundamentals I'd already have from coursework, focus
explanations on what's specific to this stack and this project.

Three docs in `docs/` drive everything: `PROJECT_DESCRIPTION.md` (architecture
and rationale — the closest thing to a stack-decisions doc, doubles as source
material for job applications), `plan.md` (task list, in Bahasa Indonesia),
`knowledge-graph.md` (a running glossary of concepts touched in this project —
see below, this is now lightweight). Read all three at the start of a session
before writing code. `docs/fetch_plan.md` is a deliberately separate post-MVP
doc (web client) — not part of the active loop until plan.md's Phase 4 is done.

Conversation and explanations happen in Bahasa Indonesia. Code, identifiers,
and concept slugs stay in English.

## Priority: ship the MVP

**As of 2026-09-17: shipping beats understanding-verification.** The
per-task explain → ask-until-no-questions → confirm → then-proceed loop that
used to gate every tagged task is retired. It was correct in spirit but wrong
in cost — it turned every task into a review session and stalled actual
progress before anything was even deployed once.

New default: **build the task, briefly note what it does and any non-obvious
decision, tick it, move on.** No waiting for confirmation before continuing.
No blocking on an "any questions?" round. If something needs real explanation
(a genuinely tricky tradeoff, a bug that took a wrong turn to fix), say so in
a sentence or two — don't skip mentioning it, just don't turn it into a
teaching session unless asked.

**Deep dives are pull, not push.** If I want the full walkthrough on
something — how JWT signing works, why a schema is shaped a certain way — I
ask for it explicitly. Don't preemptively over-explain assuming I'll want it;
assume I'll ask if I do.

**Still true regardless of pace:**
- Verify things actually work before ticking a box (run it, don't just write
  it and assume). Speed isn't an excuse for unverified checkmarks.
- If a task is genuinely blocked (needs a credential, a decision only I can
  make), say so and keep moving to unblocked work — don't stall the whole
  session on it.
- Amend plan.md when reality diverges (task needs splitting, ordering breaks,
  a tag's on the wrong task) — propose + make the edit, don't silently rewrite
  or grind through something that stopped making sense.

## knowledge-graph.md: now a lightweight glossary, not a gate

It used to require: full explanation before writing code, an evidence log of
what was asked, and status could only advance one rung per encounter after
confirmed understanding. That's gone as a *requirement* — but the file still
exists for a real reason: **so I can look back later and see what concepts
this project actually touched**, useful for interview prep, for knowing what
to brush up on, for the resume-material angle `PROJECT_DESCRIPTION.md` exists
for in the first place.

New mechanics:
- When a task tagged with a concept gets built, mark that concept `touched`
  (see simplified statuses below) with a one-line note of where/why. No
  evidence requirement, no confirmation gate, no "ask until no questions."
- If I ask for a deep dive on a concept at any point, log that as `explained`
  once I say it made sense — no back-and-forth requirement, just an honest
  "yeah that's clear."
- Nothing here blocks moving to the next task. Ever. It's a log, not a
  checkpoint.

**Simplified statuses** (replacing the old not-started/introduced/practicing/
understood ladder — existing entries keep their old status label as history,
new updates use the simplified set):
- `not-started` — not touched yet.
- `touched` — built as part of a task. Default state for anything shipped.
- `explained` — I asked for and got a walkthrough at some point. Worth
  revisiting before an interview; not a claim of mastery.

## Amending plan.md

The plan is a living document. When reality diverges — a task needs splitting,
an ordering assumption breaks, a concept tag sits on the wrong task — propose
the edit with a reason, then make it. Don't silently rewrite tasks, and don't
grind through a task that stopped making sense just because it's written down.

## Blocked tasks

If a task can't be finished right now (missing credential, waiting on a
decision), tag it `[BLOKIR-X]` in plan.md, note what unblocks it in the
"Status blokir" section, and move straight to the next unblocked task instead
of stalling. Code can be written ahead of a blocker; verification (and the
checkbox) waits for the blocker to clear.
