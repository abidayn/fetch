# Same Python version as the local venv (3.14) -- the tested version.
FROM python:3.14-slim

# Unbuffered output so logs show up in real time in Railway's logs.
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# requirements first, then the code: the install layer isn't rebuilt
# every time the code changes (faster builds).
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Railway provides the port via the PORT env var. A single worker only: the
# free-tier Supavisor connection pool is limited, and BackgroundTasks run in-process.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]