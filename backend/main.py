import logging

from fastapi import FastAPI

from routers import auth, items, search

# So enrichment logs (extraction/classifier/enrichment) show up in the
# uvicorn console -- without this only warnings and above appear.
logging.basicConfig(level=logging.INFO, format="%(levelname)s:     %(name)s - %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)  # logs every HTTP request, too noisy

app = FastAPI(title="Fetch API")

app.include_router(auth.router)
app.include_router(items.router)
app.include_router(search.router)


@app.get("/health")
def health():
    return {"status": "ok"}
