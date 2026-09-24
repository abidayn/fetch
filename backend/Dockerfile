# Versi Python sama dengan venv lokal (3.14) -- versi yang sudah teruji.
FROM python:3.14-slim

# Log langsung keluar (tanpa buffer) supaya tampil real-time di log Railway.
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# requirements dulu, baru kode: layer install tidak dibangun ulang
# setiap kali kode berubah (build lebih cepat).
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Railway memberi port lewat env var PORT. Satu worker saja: pool koneksi
# Supavisor free tier terbatas, dan BackgroundTasks berjalan in-process.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]