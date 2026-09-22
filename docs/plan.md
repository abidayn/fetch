# Fetch — Rencana Kerja

Daftar task pembangunan Fetch, dikelompokkan per fase. Setiap task punya tag
`concepts:` yang cocok dengan slug di `knowledge-graph.md` — itu cuma penanda
topik yang tersentuh (lihat `.claude/CLAUDE.md`: sejak 2026-09-17 fokusnya
shipping MVP, knowledge-graph.md jadi glosarium ringan, bukan gerbang).

**Aturan atomic**: satu task = satu hasil yang bisa diverifikasi. Kalau sebuah
baris butuh kata "dan" untuk menjelaskan hasilnya, berarti masih compound dan
harus dipecah.

**Soal urutan**: fase berurutan karena fase belakang butuh data/struktur dari
fase depan. Tapi di dalam satu fase, sebagian task bisa ditukar urutannya —
dicatat di tempatnya kalau memang begitu.

Slug konsep sengaja tetap Bahasa Inggris karena itu kunci yang menghubungkan
plan.md dengan knowledge-graph.md.

---

## Status blokir

### ~~BLOKIR-C — Developer Mode Windows belum aktif~~ (SELESAI 2026-09-18)

Sudah diaktifkan, `flutter doctor` bersih, build & run ke emulator sukses.
Dipertahankan di sini cuma sebagai riwayat.

### ~~BLOKIR-D — Splash screen macet saat cold-start lewat share intent~~ (SELESAI 2026-09-18)

**Gejala**: app ditutup total (`am force-stop`) → share link dari Chrome →
Fetch ter-launch tapi splash Android-nya tidak pernah hilang, macet permanen.

**Diagnosis** (lewat logcat + uji ulang): data selalu tersimpan benar
(`POST /items` 201 konsisten), `flutter attach` + hot restart membuktikan
Dart isolate sehat (bukan hang di Dart) — yang macet adalah splash native
Android-nya sendiri, spesifik cuma waktu Activity di-cold-create lewat intent
`ACTION_SEND`. Buka app yang sama secara normal (`ACTION_MAIN`) langsung
menampilkan semua data dengan benar, instan.

**Fix**: mekanisme auto-dismiss splash bawaan Flutter (deteksi first-frame
implisit) rupanya tidak selalu terpicu kalau Activity dibuat lewat trampoline
chooser Android (share-sheet), beda dari tap launcher biasa. Diganti dengan
kontrol eksplisit pakai `androidx.core:core-splashscreen`:
- `android/app/build.gradle.kts` — tambah dependency `androidx.core:core-splashscreen:1.0.1`
- `MainActivity.kt` — panggil `installSplashScreen()` di `onCreate()` sebelum `super.onCreate()`
- `styles.xml` (light & night) — `LaunchTheme` diganti extend `Theme.SplashScreen`

Ini memberi dismiss-signal yang terikat ke draw-pertama Activity di level
Android, bukan ke deteksi Flutter yang ternyata tidak selalu terpicu lewat
jalur trampoline itu.

**Verifikasi**: 2 dari 2 percobaan cold-start-via-share bersih berturut-turut
sukses sempurna setelah fix — app langsung tampil (spinner Flutter asli yang
berputar, bukan splash native yang macet), item tersimpan dan muncul otomatis
di list tanpa perlu buka app manual. `flutter analyze` tetap bersih.

---

## Fase 0 — Persiapan proyek

Semua task di fase ini **tidak bertag konsep** — ini murni setup dan konfigurasi,
bukan materi belajar. Kerjakan, centang, jangan sentuh knowledge-graph.

### Scaffolding

- [x] Buat proyek Flutter di folder `mobile/` (`flutter create mobile`)
- [x] Pastikan Flutter app jalan di emulator Android
- [x] Buat folder `backend/` dan virtual environment Python
- [x] Install FastAPI + uvicorn ke dalam venv
- [x] Tulis endpoint `/health` di `backend/main.py`
- [x] Pastikan backend jalan lokal (`curl localhost:8000/health` → 200)
- [x] Buat `backend/.gitignore` (venv, `.env`, `__pycache__`)
- [x] Buat `backend/.env.example` sebagai template
- [x] Install SDK Gemini (`google-genai`) dan driver Postgres (`psycopg`)
- [x] Tulis script cek `check_db.py` dan `check_gemini.py`

### Database — butuh aksi kamu (daftar akun)

- [x] Daftar akun Supabase, buat satu project Postgres
- [x] Salin connection string ke `backend/.env` sebagai `DATABASE_URL`
- [x] Aktifkan extension `pgvector` (jalankan `check_db.py`)
- [x] Pastikan `check_db.py` mencetak versi extension tanpa error (0.8.2)

### Gemini API — butuh aksi kamu (ambil API key)

- [x] Ambil API key gratis di Google AI Studio
- [x] Salin key ke `backend/.env` sebagai `GEMINI_API_KEY`
- [x] Pastikan `check_gemini.py` berhasil mencetak balasan model (model diganti ke gemini-3.6-flash, yg lama sudah discontinued)

---

## Fase 1 — Fondasi backend

Fase paling padat konsep. Lima konsep baru diperkenalkan di sini, dan tiga di
antaranya (`relational-schema-design`, `jwt-auth`, `rest-api-design`) akan muncul
lagi di fase berikutnya — jadi ini encounter pertama mereka.

### Desain skema (belum menyentuh kode)

- [x] Tentukan kolom dan constraint tabel `users`
      — concepts: relational-schema-design
- [x] Tentukan kolom struktural tabel `saved_items` (url, platform, title,
      summary, category, raw_content, created_at)
      — concepts: relational-schema-design
- [x] Tentukan relasi foreign key `saved_items.user_id` → `users.id`
      — concepts: relational-schema-design
- [x] Tentukan dimensi kolom `embedding` (pertimbangkan batas index pgvector
      2000 dimensi vs default Gemini 3072)
      — concepts: relational-schema-design
- [x] Tulis hasil desain ke `docs/data-model.md`

### ORM dan migrasi

- [x] Install SQLAlchemy dan Alembic ke venv
- [x] Buat koneksi database dan `Base` declarative di `backend/`
- [x] Tulis SQLAlchemy model untuk `users`
      — concepts: orm-migrations
- [x] Tulis SQLAlchemy model untuk `saved_items`
      — concepts: orm-migrations
- [x] Inisialisasi Alembic dan arahkan ke `DATABASE_URL`
- [x] Generate file migrasi pertama dari model (+ perbaiki bug: import pgvector.sqlalchemy hilang di file hasil autogenerate)
      — concepts: orm-migrations
- [x] Jalankan migrasi, verifikasi tabel muncul di database
      — concepts: orm-migrations

### Autentikasi

- [x] Setup hashing password (bcrypt langsung — passlib rusak dgn bcrypt 5.x)
      — concepts: jwt-auth
- [x] Tulis fungsi pembuat JWT (payload, expiry, signing)
      — concepts: jwt-auth
- [x] Tulis fungsi verifikasi/decode JWT
      — concepts: jwt-auth
- [x] Endpoint `POST /auth/register`
      — concepts: jwt-auth
- [x] Endpoint `POST /auth/login` yang mengembalikan token
      — concepts: jwt-auth

### Proteksi route

- [x] Tulis dependency `get_current_user` yang membaca header Authorization
      — concepts: middleware
- [x] Pasang dependency itu ke route yang butuh login
      — concepts: middleware
- [x] Verifikasi request tanpa token ditolak 401
      — concepts: middleware

### CRUD saved items (belum ada AI — title diisi manual dulu)

- [x] Tulis Pydantic schema request/response untuk item
      — concepts: rest-api-design
- [x] Endpoint `POST /items` (simpan url + title manual)
      — concepts: rest-api-design
- [x] Endpoint `GET /items` (list milik user yang login)
      — concepts: rest-api-design
- [x] Endpoint `GET /items/{id}`
      — concepts: rest-api-design
- [x] Endpoint `DELETE /items/{id}`
      — concepts: rest-api-design

---

## Fase 2 — Fondasi aplikasi mobile

*Bisa dikerjakan berbarengan dengan Fase 1 begitu bentuk request/response API
disepakati — tidak harus menunggu Fase 1 selesai total.*

### Struktur aplikasi

- [x] Hapus demo counter app bawaan, siapkan struktur folder `lib/`
      — concepts: flutter-app-structure
- [x] Setup routing/navigasi antar screen
      — concepts: flutter-app-structure
- [x] Buat UI screen login (+ screen register, amandemen -- perlu buat akun sebelum bisa login)
      — concepts: flutter-app-structure
- [x] Buat UI screen home/daftar item
      — concepts: flutter-app-structure

### Koneksi ke backend

- [x] Install package `http`, buat satu class API client
      — concepts: http-client-integration
- [x] Simpan JWT hasil login di secure storage
      — concepts: http-client-integration
- [x] Sisipkan header Authorization otomatis di setiap request
      — concepts: http-client-integration
- [x] Hubungkan screen login ke `POST /auth/login`
      — concepts: http-client-integration
- [x] Hubungkan screen home ke `GET /items`
      — concepts: http-client-integration

### Share-sheet (inti UX aplikasi)

- [x] Install `receive_sharing_intent`
- [x] Konfigurasi intent filter di `AndroidManifest.xml` (+ perbaiki launchMode ke singleTask, + tambah INTERNET permission yg ternyata belum ada di manifest utama)
      — concepts: share-intent-integration
- [x] Tangkap URL yang di-share saat app tertutup (cold start) — sempat macet
      di splash native Android (BLOKIR-D), sudah diperbaiki pakai
      `androidx.core:core-splashscreen` + `installSplashScreen()` di
      `MainActivity.kt`. Diuji ulang 2x bersih sesudah fix, keduanya sukses
      sempurna (lihat detail di "Status blokir" di atas).
      — concepts: share-intent-integration
- [x] Tangkap URL yang di-share saat app sudah berjalan (warm) — diuji 4x, 3
      sukses (POST /items 201 + list ter-refresh live tanpa restart). 1 kegagalan
      terjadi tepat setelah proses di-force-kill secara paksa di level OS
      (bukan cara resmi Flutter) untuk apply hot-fix -- logcat menunjukkan
      "app died, no saved state" (kematian proses tidak bersih), sangat mungkin
      artefak metode debug kami, bukan bug produk (2 percobaan warm bersih
      sesudahnya sukses semua).
      — concepts: share-intent-integration
- [x] Kirim URL hasil share ke `POST /items` — 201 Created di semua percobaan
      (cold maupun warm), termasuk kasus yang UI-nya macet di atas.
- [x] Uji end-to-end: share link → muncul di daftar — lolos untuk warm-share
      DAN cold-share (setelah fix BLOKIR-D), diuji pakai link nyata (YouTube +
      example.com) lewat share-sheet Chrome asli di emulator, bukan simulasi.

---

## Fase 3 — Pemahaman konten (AI)

*Butuh layer penyimpanan dari Fase 1 sudah jadi.*

### Ekstraksi metadata

- [x] Tulis fungsi deteksi platform dari URL (youtube/tiktok/instagram/lainnya)
      — concepts: web-scraping-content-extraction
- [x] Ekstraksi Open Graph tags sebagai jalur fallback umum (+ fallback paragraf
      awal untuk artikel tanpa meta description, mis. Wikipedia; + buang judul
      generik seperti "TikTok - Make Your Day" / "Instagram")
      — concepts: web-scraping-content-extraction
- [x] Ekstraksi via oEmbed untuk TikTok (amandemen: oEmbed Instagram butuh token
      app Facebook, jadi Instagram cukup Open Graph -- hasilnya memang tipis)
      — concepts: web-scraping-content-extraction
- [x] Ekstraksi metadata YouTube via yt-dlp
      — concepts: web-scraping-content-extraction
- [x] Tangani kasus metadata tipis tanpa error (graceful degradation) -- diuji
      dengan domain yang tidak ada & URL 404: tidak ada exception
      — concepts: web-scraping-content-extraction

### Klasifikasi via Gemini

- [x] Tulis prompt yang meminta title, summary, dan category (kategori daftar
      tetap; konten kosong -> Gemini tidak dipanggil supaya tidak halusinasi)
      — concepts: llm-prompting
- [x] Paksa output terstruktur lewat `response_schema` Gemini
      — concepts: llm-prompting
- [x] Parse dan validasi respons Gemini ke model Pydantic
      — concepts: llm-prompting
- [x] Tangani kegagalan/timeout panggilan Gemini -- timeout 20s, retry 3x dengan
      backoff untuk 429/5xx (503 "high demand" terjadi sungguhan saat uji), +
      `backfill_enrichment.py` untuk memproses ulang item yang tetap gagal
      — concepts: llm-prompting

### Integrasi ke alur simpan

- [x] Panggil ekstraksi + Gemini dari `POST /items` -- lewat FastAPI
      `BackgroundTasks` (amandemen: bukan di dalam request, karena totalnya 4-9
      detik; simpan link tidak boleh menunggu/bergantung pada Gemini). App
      mobile menampilkan "Memproses…" lalu polling tiap 4s (maks 10x) sampai
      selesai -- diuji di emulator, berubah sendiri tanpa refresh manual
- [x] Simpan title/summary/category hasil AI ke database (+ `raw_content` jadi
      penanda status: NULL = belum diproses, '' = diproses tanpa isi -- lihat
      data-model.md)
- [x] Hapus input title manual dari Fase 1 (backend `ItemCreate` + mobile
      `createItem`)

---

## Fase 4 — Pencarian RAG

*Butuh konten hasil Fase 3 untuk di-embed. Ini milestone RAG. Penjelasan
lengkap + semua angka pengukuran: `docs/rag-guide.md`.*

### Embedding

- [x] Tulis fungsi pembuat embedding dari teks via Gemini (`embeddings.py`;
      amandemen: model `gemini-embedding-2`, bukan `-001` di data-model.md --
      diuji lebih tegas membedakan relevan/tidak + vektor sudah ternormalisasi.
      Client Gemini dipindah ke `gemini.py`, dipakai bersama classifier)
      — concepts: embeddings-vector-representation
- [x] Tentukan teks mana yang di-embed -> title + summary (eksperimen 3 varian
      seri 8/8 di data kecil; keputusan pakai alasan, lihat rag-guide.md §5)
      — concepts: embeddings-vector-representation
- [x] Generate embedding otomatis saat item disimpan (di `enrichment.py`, diuji
      12 link lewat server sungguhan: semua dapat embedding, termasuk 9 yang
      klasifikasinya kena 429 kuota 5 RPM)
      — concepts: embeddings-vector-representation
- [x] Tulis script backfill embedding untuk item lama (`backfill_embeddings.py`,
      batch 50/request, `--all` untuk re-embed saat ganti model)
      — concepts: embeddings-vector-representation

### Pencarian vektor

- [x] Tulis query similarity mentah di SQL, uji manual (amandemen: psql tidak
      terinstal, dijalankan lewat psycopg -- SQL-nya sama)
      — concepts: vector-similarity-search
- [x] Pilih operator jarak -> cosine `<=>` (ketiga operator terbukti mengurutkan
      identik pada vektor ternormalisasi; cosine dipilih karena tetap benar
      kalau model berikutnya tidak menormalisasi)
      — concepts: vector-similarity-search
- [x] Buat index HNSW di kolom embedding (migrasi `66de89f6cd67`,
      `vector_cosine_ops`)
      — concepts: vector-similarity-search
- [x] Bandingkan hasil query sebelum vs sesudah index -- 25 baris: planner tetap
      pilih Seq Scan (benar, lebih murah). Benchmark tabel TEMP 10k vektor:
      80.9ms -> 1.4ms, recall@10 98% (ef_search 40)
      — concepts: vector-similarity-search

### Endpoint pencarian

- [x] Endpoint `POST /search` yang meng-embed query masuk (gagal embed -> 503)
      — concepts: rag-pipeline
- [x] Jalankan similarity search, kembalikan hasil terurut (+ `hnsw.iterative_scan`
      supaya filter `user_id` tidak memotong hasil)
      — concepts: rag-pipeline
- [x] Tambahkan ambang batas skor / limit jumlah hasil -- dua saringan:
      MIN_SCORE 0.60 + MAX_GAP_FROM_TOP 0.06 (ambang absolut saja gagal:
      "asdfghjkl" dapat 0.61). Provisional, kalibrasi ulang dengan data nyata
      — concepts: rag-pipeline

### UI pencarian

- [x] Buat UI screen search di Flutter (`search_screen.dart`, cari saat enter,
      bukan tiap ketikan)
      — concepts: flutter-app-structure
- [x] Hubungkan screen search ke `POST /search` -- diuji di emulator
      — concepts: http-client-integration
- [x] Tampilkan hasil terurut beserta skor/kategori (+ state "tidak ada yang cocok")

### Stretch (opsional, bukan syarat MVP)

- [x] Kirim item hasil retrieval kembali ke Gemini untuk jawaban naratif --
      `POST /search/answer` + `answerer.py` + tombol "Rangkum dengan AI" di
      search screen (diuji di emulator). Model `gemini-3.1-flash-lite`, sengaja
      beda dari classifier (kuota free tier per model; 3.6-flash cuma 20/hari).
      Diuji: grounding (tidak mengarang suhu rendang), konteks tak relevan
      diabaikan, prompt injection dari isi item tidak berhasil. rag-guide.md §10
      — concepts: rag-pipeline

---

## Fase 4b — Penyesuaian dari prototype visi

*Amandemen 2026-09-21. Setelah membandingkan app dengan prototype HTML milik
user (referensi rasa & alur, bukan spesifikasi), dua celah ini dinilai wajib
sebelum deploy: janji produk "simpan lalu temukan lagi" belum lengkap kalau
item yang ketemu tidak bisa dibuka, dan share yang tersimpan diam-diam terasa
seperti tidak terjadi apa-apa. Fitur lain dari prototype sengaja tidak diambil.*

- [x] Tap item (di home & hasil pencarian) membuka link di app asalnya
      (YouTube/TikTok/Instagram kalau terpasang, selain itu browser) --
      `url_launcher` + `<queries>` di AndroidManifest, `lib/util/open_link.dart`.
      Diuji di emulator: link YouTube -> app YouTube, Wikipedia -> Chrome,
      dari home maupun dari hasil pencarian
      — concepts: flutter-app-structure
- [x] Umpan balik setelah share/tempel link: bottom sheet berbahasa Inggris
      "Saved — AI is organizing this…" yang berubah jadi hasil AI (title,
      category, summary) begitu pengayaan selesai (polling `GET /items/{id}`)
      -- `lib/widgets/save_result_sheet.dart`, polling 3 dtk maks 60 dtk.
      Diuji: warm share (berubah jadi "Saved to Food & Cooking" walau Gemini
      sempat 503), cold-start share Instagram ("Couldn't read much from this
      link"). Copy sheet Inggris, isi summary tetap Bahasa Indonesia (dari
      prompt classifier)
      — concepts: http-client-integration

---

## Fase 5 — Deployment (DIKERJAKAN MANUAL OLEH USER)

*Seluruh fase ini sengaja dikerjakan sendiri oleh user, langkah demi langkah.
Claude hanya menyusun task (2026-09-21), tidak men-deploy apa pun. Setiap task
punya: **langkah**, **hasil yang diharapkan** (syarat centang), dan **kalau
gagal**. Kerjakan berurutan — task belakang bergantung pada task depan.*

**Konvensi perintah:** semua perintah terminal ditulis untuk **Git Bash**
(bukan PowerShell), dijalankan dari folder yang disebut di task. `<...>` =
ganti dengan nilaimu sendiri (tanpa tanda `<>`).

### Keputusan host (amandemen 2026-09-21)

Catatan lama bilang backend "WAJIB di region yang sama dengan DB (Sydney)".
Setelah dicek, itu tidak bisa dipenuhi dengan gratis dan sederhana:

| Opsi | Region DB kita (Sydney)? | Masalah |
|---|---|---|
| **Render (dipilih)** | Tidak ada — terdekat **Singapore** | Tidur setelah 15 menit idle, bangun ± 1 menit |
| Google Cloud Run | Ada (`australia-southeast1`) | Butuh kartu kredit; CPU default hanya aktif *selama* request, padahal pengayaan AI kita jalan **setelah** response (`BackgroundTasks`) → bisa macet |
| Fly.io | Ada (`syd`) | Tidak ada free tier untuk akun baru |
| Railway | Tidak ada Sydney | Hanya kredit trial |

**Dipilih: Render, region Singapore, lewat Docker.** Jarak Singapore↔Sydney
± 90–100 ms per query → satu request ± 4 query ≈ 0,4 detik ke DB. Masih jauh
lebih cepat dari laptop↔Sydney (± 343 ms/query) yang sudah kita pakai selama
ini. Kalau nanti terasa lambat, opsi lanjutan: pindahkan project Supabase ke
Singapore (`ap-southeast-1`) — bukan bagian fase ini.

**Fakta repo yang membentuk task di bawah** (dicek 2026-09-21):
- Python lokal **3.14** → Dockerfile memakai image `python:3.14-slim` supaya
  versinya sama persis dengan yang sudah teruji.
- `DATABASE_URL` sudah memakai **Supavisor session pooler**
  (`aws-0-ap-southeast-2.pooler.supabase.com:5432`). Ini penting: koneksi
  *direct* Supabase (`db.<ref>.supabase.co`) hanya IPv6, dan Render tidak
  mendukung IPv6 keluar. Jangan ganti ke direct connection.
- Folder `FETCH/` **belum** jadi git repo; Render men-deploy dari GitHub.
- Dev dan production memakai **database Supabase yang sama** (tidak ada DB
  production terpisah). Konsekuensi: akun & item uji ikut terlihat di
  production, dan migrasi sudah otomatis ter-apply.
- Kuota Gemini gratis (20 request/hari/model untuk klasifikasi) **dipakai
  bersama** oleh laptop dan server karena API key-nya sama.

---

### 5.1 Git & GitHub

- [ ] **Buat `.gitignore` di root repo** (`FETCH/.gitignore`)
      — concepts: api-key-secrets-management
      - Langkah: buat file `FETCH/.gitignore` berisi persis:
        ```
        # Secret -- JANGAN PERNAH di-commit
        .env
        **/.env
        # Python
        backend/venv/
        __pycache__/
        *.pyc
        # Pengaturan lokal Claude Code
        .claude/settings.local.json
        # Output build
        mobile/build/
        *.apk
        ```
        (`backend/.gitignore` dan `mobile/.gitignore` yang sudah ada tetap
        dipakai; file root ini jaring pengaman tambahan.)
      - Hasil: file ada di root `FETCH/`.
- [ ] **Inisialisasi git di root repo**
      - Langkah (di `FETCH/`): `git init -b main`
      - Hasil: muncul folder tersembunyi `FETCH/.git`; `git status` jalan
        tanpa error "not a git repository".
- [ ] **Buktikan `.env` tidak akan ikut ter-commit** — *jangan dilewati*
      — concepts: api-key-secrets-management
      - Langkah (di `FETCH/`):
        1. `git check-ignore -v backend/.env` → harus mencetak baris aturan
           yang mengabaikannya (mis. `.gitignore:2:.env  backend/.env`).
        2. `git status --short | grep -i "\.env"` → hanya boleh muncul
           `backend/.env.example`, **tidak boleh** `backend/.env`.
        3. `git status --short | grep venv` → harus kosong.
      - Kalau gagal: perbaiki `.gitignore` dulu. Jangan lanjut sebelum ketiga
        cek ini lolos.
- [ ] **Commit pertama**
      - Langkah: `git add .` lalu `git commit -m "Initial commit: Fetch MVP (Fase 0-4b)"`
      - Hasil: `git log --oneline` menampilkan 1 commit.
- [ ] **Scan secret di isi commit** — cek kedua setelah commit
      — concepts: api-key-secrets-management
      - Langkah (di `FETCH/`), ketiganya harus **tidak mengeluarkan apa-apa**:
        1. `git grep -n "AIza"` (awalan API key Google/Gemini)
        2. `git grep -n "pooler.supabase.com"` (host database)
        3. `git grep -n "JWT_SECRET_KEY=."` (secret JWT yang terisi)
      - Kalau ada yang muncul: **jangan push.** Hapus secret itu dari file,
        lalu `git commit --amend` (belum pernah di-push, jadi aman diubah).
        Kalau secret sudah terlanjur ter-push ke GitHub, anggap bocor: buat
        ulang API key Gemini, reset password DB di Supabase, dan buat JWT
        secret baru.
- [ ] **Buat repo GitHub privat**
      - Langkah: github.com → New repository → nama mis. `fetch` →
        **Private** → jangan centang "Add README/.gitignore" (repo harus
        kosong) → Create.
      - Hasil: halaman repo kosong berisi URL `https://github.com/<user>/fetch.git`.
- [ ] **Push ke GitHub**
      - Langkah (di `FETCH/`):
        `git remote add origin https://github.com/<user>/fetch.git`
        lalu `git push -u origin main`
      - Hasil: file tampil di halaman GitHub. Klik folder `backend/` dan
        pastikan **tidak ada** `.env` maupun `venv/` di sana.

### 5.2 File konfigurasi deploy

- [ ] **Tulis `backend/Dockerfile`**
      — concepts: deployment-hosting
      - Langkah: buat file `backend/Dockerfile` berisi persis:
        ```dockerfile
        # Versi Python sama dengan venv lokal (3.14) -- versi yang sudah teruji.
        FROM python:3.14-slim

        # Log langsung keluar (tanpa buffer) supaya tampil real-time di dashboard Render.
        ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

        WORKDIR /app

        # requirements dulu, baru kode: layer install tidak dibangun ulang
        # setiap kali kode berubah (build lebih cepat).
        COPY requirements.txt .
        RUN pip install --no-cache-dir -r requirements.txt

        COPY . .

        # Render memberi port lewat env var PORT. Satu worker saja: pool koneksi
        # Supavisor free tier terbatas, dan BackgroundTasks berjalan in-process.
        CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
        ```
      - Hasil: file ada di `backend/Dockerfile` (tanpa ekstensi).
- [ ] **Tulis `backend/.dockerignore`**
      — concepts: api-key-secrets-management
      - Langkah: buat `backend/.dockerignore` berisi:
        ```
        venv/
        .env
        __pycache__/
        *.pyc
        ```
      - Kenapa: tanpa ini, `COPY . .` akan memasukkan `.env` (secret!) dan
        folder venv Windows (ratusan MB, tidak jalan di Linux) ke dalam image.
- [ ] *(Opsional, hanya kalau Docker Desktop terpasang)* **Uji build image di laptop**
      - Langkah (di `backend/`): `docker build -t fetch-api .` lalu
        `docker run --rm -p 8000:8000 --env-file .env fetch-api`, lalu di
        terminal lain `curl localhost:8000/health`.
      - Hasil: `{"status":"ok"}`. Kalau Docker tidak terpasang, lewati —
        build log Render di 5.4 jadi pengujiannya.
- [ ] **Commit & push file deploy**
      - Langkah (di `FETCH/`): `git add backend/Dockerfile backend/.dockerignore`
        → `git commit -m "Add Dockerfile for Render deploy"` → `git push`
      - Hasil: kedua file terlihat di GitHub.

### 5.3 Render: akun, service, environment variables

- [ ] **Buat akun Render**
      — concepts: deployment-hosting
      - Langkah: render.com → Get Started → **Sign up with GitHub** (supaya
        Render bisa membaca repo privatmu).
      - Hasil: masuk ke dashboard Render.
- [ ] **Buat Web Service dari repo**
      — concepts: deployment-hosting
      - Langkah: New + → **Web Service** → pilih repo `fetch` (kalau tidak
        muncul: "Configure account" → beri akses ke repo itu). Isi:
        - Name: `fetch-api` (menentukan URL: `https://fetch-api.onrender.com`;
          kalau nama sudah dipakai orang, Render menambah akhiran acak)
        - Region: **Singapore (Southeast Asia)**
        - Branch: `main`
        - Root Directory: `backend`
        - Language/Runtime: **Docker** (Render mendeteksi Dockerfile)
        - Instance Type: **Free**
      - **JANGAN klik Deploy dulu** — isi environment variables di dua task
        berikut (di halaman yang sama, bagian "Environment Variables"). Kalau
        terlanjur deploy, tidak apa-apa: deploy pertama akan crash karena env
        kosong; isi env lalu deploy ulang.
- [ ] **Buat JWT secret baru khusus production**
      — concepts: api-key-secrets-management
      - Langkah (di `backend/`):
        `venv/Scripts/python.exe -c "import secrets; print(secrets.token_urlsafe(48))"`
      - Simpan hasilnya sementara (jangan ditempel di chat, file repo, atau
        screenshot). Kenapa baru, bukan menyalin dari `.env`: secret lokal
        sudah berkali-kali tersentuh selama development; production pantas
        punya secret sendiri. Token lama dari laptop jadi tidak berlaku di
        server — memang itu tujuannya.
- [ ] **Isi environment variables di Render**
      — concepts: api-key-secrets-management
      - Langkah: bagian Environment Variables → Add, tiga baris:

        | Key | Value |
        |---|---|
        | `DATABASE_URL` | salin persis dari `backend/.env` (yang host-nya `...pooler.supabase.com:5432`) |
        | `GEMINI_API_KEY` | salin dari `backend/.env` |
        | `JWT_SECRET_KEY` | hasil task sebelumnya |

      - Perhatikan: tanpa tanda kutip, tanpa spasi di awal/akhir. Secret
        diisi di dashboard, **bukan** di file mana pun di repo — itu inti dari
        manajemen secret lewat environment variable.
      - Hasil: tiga env var tersimpan.
- [ ] **Set health check path**
      - Langkah: Advanced (atau Settings setelah service jadi) →
        Health Check Path: `/health`
      - Kenapa: Render baru mengalihkan trafik ke versi baru setelah
        `/health` menjawab 200 — deploy yang rusak tidak menggantikan yang sehat.

### 5.4 Deploy & verifikasi server

- [ ] **Deploy pertama sampai status "Live"**
      — concepts: deployment-hosting
      - Langkah: Create Web Service / Deploy → buka tab **Logs**, tunggu
        (build pertama beberapa menit: install requirements termasuk yt-dlp).
      - Hasil: log berakhir dengan `Uvicorn running on http://0.0.0.0:...`
        dan status service **Live**.
      - Kalau gagal: baca baris error pertama di log build.
        `ERROR: No matching distribution found for <paket>` → paket itu belum
        punya versi untuk Python 3.14 Linux; catat nama paketnya.
        `KeyError: 'GEMINI_API_KEY'` / `JWT_SECRET_KEY` → env var belum diisi
        atau salah nama.
- [ ] **Verifikasi `/health` dari URL publik**
      — concepts: deployment-hosting
      - Langkah (Git Bash): `curl -i https://<nama-service>.onrender.com/health`
      - Hasil: `HTTP/2 200` dan body `{"status":"ok"}`. Buka juga URL yang
        sama di browser HP (pakai data seluler, bukan WiFi rumah) — harus
        tampil teks yang sama.
- [ ] **Verifikasi migrasi database = head**
      — concepts: orm-migrations
      - Konteks: karena production memakai DB yang sama dengan dev, migrasi
        tidak perlu dijalankan lagi — tapi harus **dibuktikan**, bukan diasumsikan.
      - Langkah (di `backend/`, laptop): `venv/Scripts/python.exe -m alembic current`
      - Hasil: mencetak `66de89f6cd67 (head)`.
      - Kalau hasilnya revisi lain / kosong: `venv/Scripts/python.exe -m alembic upgrade head`,
        lalu cek ulang.
- [ ] **Uji login production dengan curl**
      - Langkah (Git Bash), pakai akun uji yang sudah ada:
        ```bash
        curl -s -X POST https://<nama-service>.onrender.com/auth/login \
          -H "Content-Type: application/json" \
          -d '{"email":"rag-test@example.com","password":"ragtest12345"}'
        ```
      - Hasil: JSON berisi `"access_token":"eyJ..."`. Salin nilai token itu
        (tanpa kutip) untuk task-task berikut.
      - Kalau `500`: buka Logs Render — biasanya `DATABASE_URL` salah.
- [ ] **Uji daftar item production**
      - Langkah: `curl -s https://<nama-service>.onrender.com/items -H "Authorization: Bearer <token>"`
      - Hasil: JSON array berisi item-item akun uji (Rendang, Deadlift, dst.) —
        bukti server membaca database yang sama.
- [ ] **Uji pencarian semantik production**
      - Langkah:
        ```bash
        curl -s -w "\n%{time_total}s\n" -X POST https://<nama-service>.onrender.com/search \
          -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
          -d '{"query":"olahraga angkat beban"}'
        ```
      - Hasil: hasil pertama *Deadlift*. Angka di baris terakhir = latensi
        production pertamamu (di laptop: ± 2 detik) — catat.
- [ ] **Uji simpan + pengayaan AI di server**
      - Langkah:
        ```bash
        curl -s -X POST https://<nama-service>.onrender.com/items \
          -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
          -d '{"url":"https://en.wikipedia.org/wiki/Gado-gado"}'
        ```
        Tunggu ± 15 detik, lalu buka tab Logs Render.
      - Hasil: log berisi `enrichment - item ... diperkaya: platform=generic ... ai=True embedding=True`.
      - Kalau `ai=False` dengan `429` di log: kuota harian Gemini habis
        (dipakai bersama dengan laptop). Bukan bug deploy — coba lagi besok.
- [ ] **Uji ekstraksi YouTube dari server**
      - Langkah: ulangi task sebelumnya dengan URL
        `https://www.youtube.com/watch?v=jNQXAC9IVRw`, lalu cek log.
      - Hasil yang mungkin — **catat mana yang terjadi**:
        - `sources=['yt_dlp']` → yt-dlp jalan normal dari server.
        - `sources=['open_graph']` + baris `yt-dlp gagal ... Sign in to confirm you're not a bot`
          → YouTube memblokir IP datacenter (umum terjadi di host cloud). Item
          tetap tersimpan dengan judul + deskripsi dari Open Graph
          (graceful degradation bekerja sesuai desain), hanya lebih tipis.
          Catat sebagai keterbatasan production, bukan kegagalan task.
- [ ] **Uji perilaku cold start (service tidur)**
      - Langkah: jangan sentuh server ≥ 20 menit (dashboard menunjukkan
        service tidur). Lalu jalankan lagi
        `curl -i -w "\n%{time_total}s\n" https://<nama-service>.onrender.com/health`.
      - Hasil: tetap `200`, tapi butuh ± 30–60 detik. Catat angkanya — ini
        yang akan dirasakan saat share pertama setelah HP lama tidak dipakai.

### 5.5 Build app untuk production

- [ ] **Buat base URL API bisa diatur saat build**
      - Langkah: di `mobile/lib/api/api_client.dart`, ganti getter `_baseUrl`
        (sekarang hardcode `10.0.2.2`) menjadi:
        ```dart
        /// Diisi saat build: --dart-define=API_BASE_URL=https://...
        /// Kalau tidak diisi (flutter run biasa), jatuh ke backend lokal:
        /// 10.0.2.2 = alias emulator Android untuk localhost laptop.
        static const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

        static String get _baseUrl {
          if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
          if (Platform.isAndroid) return 'http://10.0.2.2:8000';
          return 'http://127.0.0.1:8000';
        }
        ```
      - Kenapa `--dart-define`, bukan langsung ganti string-nya: emulator
        tetap bisa dipakai untuk development tanpa mengedit kode bolak-balik.
      - Hasil: `/c/flutter/bin/flutter analyze` (di `mobile/`) → `No issues found!`
- [ ] **Commit perubahan base URL**
      - Langkah: `git add mobile/lib/api/api_client.dart` →
        `git commit -m "Configurable API base URL via dart-define"` → `git push`
- [ ] **Build release APK dengan URL production**
      - Langkah (di `mobile/`, Git Bash):
        `/c/flutter/bin/flutter build apk --release --dart-define=API_BASE_URL=https://<nama-service>.onrender.com`
        (tanpa garis miring `/` di akhir URL — kode menambahkan `/items` dst.
        sendiri; garis miring ganda bisa bikin 404.)
      - Hasil: `√ Built build\app\outputs\flutter-apk\app-release.apk (xx.xMB)`.
      - Catatan: APK ini ditandatangani dengan **debug key** (setting bawaan
        di `android/app/build.gradle.kts`). Cukup untuk sideload ke HP sendiri;
        baru jadi masalah kalau suatu hari mau ke Play Store.

### 5.6 Install ke HP fisik (Infinix)

- [ ] **Aktifkan USB debugging di HP**
      - Langkah: Pengaturan → Tentang ponsel → ketuk **Nomor versi / Build
        number** 7× sampai muncul pesan mode developer aktif → kembali ke
        Pengaturan → Sistem → **Opsi pengembang** → nyalakan **USB debugging**.
        (Letak menu di XOS/Infinix bisa sedikit beda — cari "Opsi pengembang".)
      - Hasil: menu Opsi pengembang ada dan USB debugging aktif.
- [ ] **Sambungkan HP ke adb**
      - Langkah: colok USB → di HP, izinkan "Allow USB debugging?" (centang
        "Always allow") → di Git Bash: `/c/Android/Sdk/platform-tools/adb.exe devices`
      - Hasil: satu baris `<serial>   device` (serial HP-mu sebelumnya
        terlihat sebagai `102682537P001273`). Kalau tertulis `unauthorized`:
        cabut-colok, lalu setujui dialog di HP.
- [ ] **Install APK release ke HP**
      - Langkah (di `mobile/`):
        `/c/Android/Sdk/platform-tools/adb.exe -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk`
        (`-s <serial>` penting kalau emulator juga sedang menyala.)
      - Hasil: `Success`, ikon app "mobile" muncul di HP.
      - Kalau `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: ada versi lama dengan
        tanda tangan berbeda →
        `/c/Android/Sdk/platform-tools/adb.exe -s <serial> uninstall com.example.mobile`,
        lalu install ulang.
      - Alternatif tanpa kabel: kirim file `app-release.apk` ke HP (Google
        Drive/Telegram), buka di HP, izinkan "Instal aplikasi tidak dikenal"
        untuk app pembuka file itu.

### 5.7 Uji end-to-end di HP (production sungguhan)

Semua uji di bawah pakai **data seluler** (matikan WiFi) supaya terbukti app
bicara ke server publik, bukan ke laptop. Backend lokal di laptop boleh mati.

- [ ] **Login di HP ke server production**
      - Langkah: buka app → login dengan akunmu (akun yang sama dengan di
        emulator — DB-nya sama).
      - Hasil: home menampilkan item-item yang sama seperti di emulator.
- [ ] **Share link YouTube dari app YouTube**
      - Langkah: app YouTube → buka video apa saja → Share → pilih app Fetch
        ("mobile").
      - Hasil: Fetch terbuka, muncul sheet **"Saved"** → *"AI is organizing
        this…"* → berubah jadi **"Saved to <kategori>"** dengan judul &
        ringkasan. Item baru ada di puncak daftar.
- [ ] **Share link TikTok dari app TikTok**
      - Langkah: app TikTok → video apa saja → Share → **Lainnya/More** →
        pilih Fetch.
      - Hasil: sheet berubah jadi hasil AI dari caption video (bukti oEmbed
        TikTok jalan dari server). Kalau Fetch tidak muncul di daftar share
        TikTok, pakai "Salin tautan" lalu tempel lewat tombol **+** di Fetch —
        catat mana yang berhasil.
- [ ] **Share dari Instagram (kasus data tipis)**
      - Langkah: app Instagram → post apa saja → Share → Fetch.
      - Hasil: sheet menampilkan *"Couldn't read much from this link, so it's
        saved as-is."* dan item tampil sebagai URL. Ini perilaku yang
        diharapkan (Instagram menutup akses tanpa login), bukan bug.
- [ ] **Share saat app tertutup total (cold start di HP asli)**
      - Langkah: tutup Fetch dari recent apps (swipe) → share link dari Chrome
        ke Fetch.
      - Hasil: app terbuka (tidak macet di splash — bug BLOKIR-D dulu), sheet
        "Saved" muncul, item tersimpan.
- [ ] **Share pertama setelah server tidur**
      - Langkah: jangan buka Fetch ≥ 20 menit → share satu link.
      - Hasil: tetap tersimpan, tapi penyimpanan bisa tertahan ± 30–60 detik
        (server Render sedang bangun). Catat pengalamanmu: masih bisa
        diterima, atau perlu ditangani nanti (mis. ping berkala)?
- [ ] **Cari item yang barusan disimpan**
      - Langkah: ikon cari → ketik kalimat yang menggambarkan video/link tadi
        *dengan kata-kata lain* (bukan judulnya) → enter.
      - Hasil: item itu muncul di hasil teratas.
- [ ] **Rangkum dengan AI di HP**
      - Langkah: dari hasil pencarian tadi, tap **Rangkum dengan AI**.
      - Hasil: muncul jawaban bersitasi `[1]`. Catat lama tunggunya.
- [ ] **Buka item dari HP ke app asalnya**
      - Langkah: tap item YouTube di daftar/hasil cari; lalu tap item TikTok.
      - Hasil: masing-masing terbuka di app YouTube / app TikTok (bukan di
        browser), karena kedua app terpasang di HP.
- [ ] **Catat angka & temuan production ke PROJECT_DESCRIPTION.md**
      - Langkah: tambahkan ke `docs/PROJECT_DESCRIPTION.md` bagian
        "Deployment": host & region (Render Singapore), latensi `/search` dari
        curl, lama cold start, hasil uji yt-dlp dari server, dan keterbatasan
        yang ditemukan. Doc itu memang minta angka nyata setelah project jalan.
      - Hasil: bagian Deployment berisi angka hasil pengukuranmu sendiri.

---

## Fase 6 — Polish (opsional, di luar syarat MVP)

*Loop save → understand → retrieve sudah jalan tanpa bagian ini.*

### Hybrid retrieval

*Vector search murni nggak cukup begitu query punya komponen terstruktur —
"video masak dari bulan lalu" separuhnya semantik, separuhnya filter. Ditunda ke
sini biar Fase 4 fokus RAG dasar dulu.*

- [ ] Tambahkan filter kategori pada query pencarian
      — concepts: hybrid-retrieval
- [ ] Tambahkan filter rentang waktu (`created_at`) pada query pencarian
      — concepts: hybrid-retrieval
- [ ] Gabungkan filter terstruktur dan similarity dalam satu query SQL
      — concepts: hybrid-retrieval
- [ ] Uji query campuran (semantik + filter) memberi hasil yang masuk akal
      — concepts: hybrid-retrieval

- [ ] Endpoint `PATCH /items/{id}` untuk edit
- [ ] UI edit item di Flutter
- [ ] UI hapus item di Flutter
- [ ] Screen browse berdasarkan kategori
- [ ] Loading state di semua screen yang memanggil API
- [ ] Error handling dan tombol retry di API client
- [ ] Empty state saat belum ada item tersimpan
