# Fetch Architecture

## 1. Goal

This project is a small, single-user personal content retrieval system with:
- mobile capture via Android share sheet
- backend metadata extraction
- AI classification and summarization
- vector-based semantic search

The app is intentionally simple:
- one backend
- one mobile app
- one relational database with pgvector
- one AI provider

---

## 2. High-level architecture

```text
Android share sheet
        |
        v
Flutter Mobile App
        |
        v
FastAPI Backend
   - auth
   - item save flow
   - metadata extraction
   - AI classification
   - embeddings
   - search
        |
        +----> PostgreSQL + pgvector
        |
        +----> Google Gemini API