# Fetch PRD

## 1. Overview

Fetch is a mobile-first personal content saving app for short-form video and web content. The core pain point is: users save links and videos with good intentions, but later cannot find them quickly because saved content is unstructured and hard to search.

Fetch solves this by:
- accepting a shared link from the user's phone
- extracting whatever metadata is available
- using Gemini to infer a title, summary, and category
- storing it in a database with a vector embedding
- allowing natural language search later

The MVP focuses on:
- Android share-intent capture
- authenticated save flow
- AI-powered organization
- RAG-based natural-language search

The MVP does not include:
- web app
- multi-user SaaS
- full social media workspace
- content editing dashboard
- generative answer over retrieved items

---

## 2. Problem

People regularly save content across TikTok, Instagram, YouTube, and other websites, but the current retention tools are poor:
- saved content is often buried in a flat list
- searching by exact text or title is unreliable
- users usually remember the idea, not the exact title or platform
- manual tagging is too much friction

This creates a recurring problem: “I saved it before, but I can’t find it again.”

---

## 3. Target user

Single user / personal power user:
- saves content intentionally
- uses multiple platforms
- wants to find things later without manual organization
- values speed over perfect metadata
- is comfortable with a personal, non-enterprise app

This is not a team product and not a public platform.

---

## 4. Core user flow

### Save flow
1. User shares a link from TikTok, Instagram, YouTube, or a generic webpage.
2. Fetch receives the URL through the Android share sheet.
3. Backend extracts basic metadata from the URL.
4. Gemini classifies and summarizes the content.
5. Backend stores the item and generates an embedding.
6. Item appears in the user’s saved list.

### Search flow
1. User opens the search screen.
2. User enters a natural-language query, e.g.:
   - “workout videos from last month”
   - “quick recipe videos with pasta”
   - “that article about resume tips”
3. Backend embeds the query and performs similarity search against saved items.
4. Query results are ranked by relevance and filtered by category/time if needed.
5. User can see saved items relevant to that search.

---

## 5. Product goals

### Primary goals
- Save a link with minimal user effort
- Automatically organize saved content
- Search saved items using natural language
- Keep the flow fast and simple for one user

### Secondary goals
- Support hybrid retrieval:
  - semantic similarity
  - category filter
  - time filter

---

## 6. Non-goals

The MVP explicitly excludes:
- web client
- multi-user accounts
- editing/deleting content from a complex dashboard
- generating conversational answers over search results
- full search relevance tuning as a science project
- a polished social feed or content browsing UI

---

## 7. Functional requirements

### 7.1 Authentication
- Users can register and log in.
- API endpoints for items and search require authentication.
- JWT tokens are used for mobile clients.

### 7.2 Save item
- User can save a URL.
- Backend extracts metadata.
- Item is classified into a category such as:
  - video
  - article
  - tutorial
  - recipe
  - entertainment
  - etc.
- Stored item includes:
  - title
  - summary
  - category
  - platform
  - source URL
  - created timestamp
  - embedding

### 7.3 Search
- User can search via natural-language queries.
- Search supports:
  - semantic similarity
  - time range filter
  - category filter

### 7.4 Mobile app
- Flutter app supports:
  - login/register
  - saved item list
  - search
  - native Android share-intent integration

---

## 8. Success metrics

For MVP, success means:
- A user can share a URL from another app and save it in one flow
- AI classification produces useful title/summary/category
- Search finds relevant items from rough memory, not exact title match
- The user can actually use the search loop repeatedly

### Example practical success tests
- Save a YouTube tutorial link
- Search “beginner workout routine”
- The relevant saved item appears near the top
- Save a TikTok cooking clip
- Search “easy pasta dinner”
- The item is retrieved by semantic similarity

---

## 9. Risks / assumptions

### Assumptions
- Some platforms expose little metadata by design.
- AI output is useful but not perfect.
- Users do not expect perfect categorization; useful retrieval is the main goal.

### Risks
- Some social platform URLs may not contain enough data.
- API rate limits or model latency may affect save flow.
- Embedding quality depends on stored text quality.

### Mitigations
- Graceful degradation when metadata is thin
- Store raw extracted data when available
- Favor useful retrieval over perfect categorization
- Keep AI scope narrow and controlled

---

## 10. MVP definition

Release when:
- user can register/login
- user can share a URL from Android
- item gets saved and stored
- backend classifies and summarizes content
- comment is not required
- user can search saved items by natural language
- app works end-to-end locally

---

## 11. Open questions

- Should title/summary/category be generated only from available metadata or should raw page text also be used when possible?
- Should the app support only Android in MVP or also iOS later?
- Should search results return only ranked items or also a generated conversational answer?
- Is the app single-user only in v1 or should multi-account support be considered later?

---

## 12. Revision history

- v0.1: Initial PRD drafted from current product direction and MVP plan