import logging

from fastapi import FastAPI

from routers import auth, items, search

# Supaya log pengayaan (extraction/classifier/enrichment) ikut tampil di
# console uvicorn -- tanpa ini cuma warning ke atas yang muncul.
logging.basicConfig(level=logging.INFO, format="%(levelname)s:     %(name)s - %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)  # tiap request HTTP di-log, terlalu ramai

app = FastAPI(title="Fetch API")

app.include_router(auth.router)
app.include_router(items.router)
app.include_router(search.router)


@app.get("/health")
def health():
    return {"status": "ok"}
