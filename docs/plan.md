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

### Keputusan host — status saat ini + riwayat perubahan

> **Status saat ini (2026-09-23):** host = **Railway**, region = **Singapore
> kalau tersedia untuk plan trial/free** (dicek di task pertama §5.3 — belum
> pasti, lihat catatan di situ), database = **Supabase Singapore**, repo
> GitHub = **public**. Bagian di bawah ini riwayat kenapa sampai ke sini —
> kalau cuma mau tahu status terkini, cukup baca kotak ini saja.

#### Riwayat keputusan (urutan kronologis)

**1. Keputusan awal (2026-09-21): Render, Singapore.**

Perbandingan awal (kolom "Region DB" merujuk ke Sydney, lokasi DB waktu itu
sebelum dipindah):

| Opsi | Region DB kita (Sydney)? | Masalah |
|---|---|---|
| **Render (dipilih saat itu)** | Tidak ada — terdekat Singapore | Tidur setelah 15 menit idle, bangun ± 1 menit |
| Google Cloud Run | Ada (`australia-southeast1`) | Butuh kartu kredit; CPU default cuma aktif *selama* request, padahal `BackgroundTasks` kita jalan **setelah** response → bisa macet |
| Fly.io | Ada (`syd`) | Tidak ada free tier untuk akun baru |
| Railway | Tidak ada Sydney | Waktu itu dikira "cuma kredit trial" — ternyata salah, ada plan Free permanen juga (lihat poin 3) |

**2. Amandemen 2026-09-22 — database ikut dipindah ke Singapore.**

Alasannya:
- Rencana awal menerima ± 90–100 ms/query Render(Singapore)↔DB(Sydney)
  sebagai "cukup baik" — tapi itu keliru untuk diterima permanen.
- Latensi itu bukan cuma soal `/search` (yang memang didominasi panggilan
  Gemini 0,5–20 detik, jadi 90 ms tidak terasa).
- Latensi itu **juga kena ke setiap** `POST /items` (simpan awal),
  `GET /items`, `DELETE`, dan login — operasi murni DB tanpa AI yang
  terjadi berkali-kali di setiap sesi.
- Menerimanya berarti membayar pajak itu selamanya di setiap ketukan.
- Karena project Supabase waktu itu cuma berisi data uji (~25–30 baris,
  tidak ada user asli), biaya pindah saat itu nyaris nol. Menunda sampai
  ada data user sungguhan akan jauh lebih berisiko.

Efek samping yang perlu diketahui, di luar soal region: project Supabase
gratis **otomatis pause setelah 1 minggu tidak dipakai** — ini beda dari,
dan di luar, soal tidurnya host backend. Kalau app tidak disentuh seminggu,
ada dua lapis "bangun tidur" untuk diperhitungkan, bukan cuma satu.

**3. Amandemen 2026-09-22 #2 — Render minta kartu kredit, pindah ke Railway.**

Waktu benar-benar daftar, Render meminta kartu kredit di awal (bukan cuma
"kalau kepakai lebih dari limit" seperti dugaan riset awal — kebijakan itu
sepertinya berubah, atau berlaku beda per akun/region).

Kabar baiknya: Railway juga punya region **Southeast Asia (Singapore)**
(`asia-southeast1-eqsg3a`), jadi keputusan migrasi DB ke Singapore tetap
relevan. Trial akun baru dapat kredit gratis $5 selama 30 hari, tanpa kartu
kredit. Setelah itu, akun otomatis turun ke plan **Free: $1 kredit/bulan** —
tetap tanpa kartu, tapi jauh lebih kecil dari asumsi lama soal Render.

Konsekuensi jujur yang perlu diketahui, beda dari asumsi Render sebelumnya:
- Estimasi kasar biaya kalau backend jalan 24/7 sebulan penuh (RAM+CPU
  minimal): **± $3/bulan** — lebih besar dari jatah $1/bulan plan Free.
  Artinya **tidak realistis dibiarkan menyala terus-menerus selamanya**
  kecuali suatu saat siap pasang kartu.
- Mitigasi: Railway punya fitur **Serverless** (tidur otomatis setelah 5
  menit tanpa trafik) tapi **harus diaktifkan manual** — beda dari Render
  yang tidur otomatis by default. Ada task khusus mengaktifkannya di §5.4.
  Dengan ini aktif, biaya idle mendekati nol, cuma kena kredit saat benar-
  benar dipakai (uji coba, demo).
- Pemilihan region **belum pasti tersedia untuk akun trial/free** — ada
  laporan komunitas (walau agak lama) bahwa pemilihan region pernah
  dibatasi untuk plan berbayar. Task pertama di §5.3 sengaja menyuruh cek
  ini di awal, bukan di akhir, supaya kalau ternyata terkunci, ketahuan
  sebelum banyak langkah lain dikerjakan sia-sia.
- Wake-up dari tidur (Serverless) bisa memunculkan **1x respons 502** di
  request pertama sebelum berhasil, beda dari Render yang cuma lambat
  tanpa error. UI mobile kita belum menangani retry otomatis untuk ini —
  kalau kejadian, coba lagi manual (refresh/re-share).

**4. Amandemen 2026-09-23 — akun Railway baru, repo dijadikan public.**

Akun Railway pertama kepakai trial-nya sia-sia (sempat dicoba dari sesi
lain, belum sampai deploy). Solusinya:
- Buat akun Railway baru (trial $5/30-hari reset).
- Repo GitHub diubah jadi **public** supaya gampang di-connect ke akun
  baru. Ini aman dari sisi secret — `.env` sudah terverifikasi tidak
  pernah ter-track sejak §5.1, jadi tidak ada yang "bocor" cuma karena
  repo terbuka.

Bug nyata ketemu & sudah di-fix saat ini juga — detailnya ada di catatan
task "Set Root Directory ke `backend`" di §5.3.

#### Fakta repo yang membentuk task di §5.0–5.7

- Python lokal **3.14** → Dockerfile memakai image `python:3.14-slim` supaya
  versinya sama persis dengan yang sudah teruji.
- `DATABASE_URL` memakai **Supavisor session pooler**, bukan koneksi direct.
  Ini penting: koneksi *direct* Supabase (`db.<ref>.supabase.co`) hanya
  IPv6, dan kebanyakan PaaS gratis (termasuk Railway) tidak mendukung IPv6
  keluar. Project Singapore juga wajib pakai pooler (host-nya
  `aws-0-ap-southeast-1...` — dengan **-1** bukan **-2** yang Sydney,
  gampang tersalah-baca).
- Folder `FETCH/` sudah jadi git repo dan sudah di-push ke GitHub (§5.1).
- Dev dan production tetap memakai **satu database Supabase yang sama**
  (Singapore) — bukan DB production terpisah.
- Kuota Gemini gratis (20 request/hari/model untuk klasifikasi) **dipakai
  bersama** oleh laptop dan server karena API key-nya sama.

---

### 5.0 Migrasi database: Supabase Sydney → Singapore

*Dikerjakan sebelum §5.1 supaya `DATABASE_URL` yang dipakai di git commit/env
Railway (§5.3) sudah final, tidak perlu diganti dua kali.*

- [x] **Buat project Supabase baru di region Singapore**
      — concepts: deployment-hosting
      - Langkah: supabase.com/dashboard → New Project → **beda organisasi
        atau project baru** (bukan menimpa yang lama — free tier boleh 2
        project aktif) → Region: **Southeast Asia (Singapore)** → set
        database password baru (beda dari yang lama) → Create.
      - Simpan password itu sementara, jangan ditempel di chat/file repo.
      - Hasil: dashboard project baru muncul, status "Setting up project"
        lalu jadi "Active".
- [x] **Aktifkan pgvector di project baru & catat connection string**
      — concepts: relational-schema-design
      - Langkah: di dashboard project baru → **Connect** (tombol di navbar
        atas) → tab **Session pooler** (bukan "Direct connection" — alasan di
        catatan fakta repo di atas) → salin connection string-nya.
      - Hasil: connection string berbentuk
        `postgresql://postgres.<ref-baru>:<password>@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres`.
        Perhatikan `ap-southeast-1` (Singapore), bukan `-2` (Sydney).
- [x] **Uji koneksi & aktifkan extension pgvector di project baru**
      — concepts: relational-schema-design
      - Langkah (di `backend/`, Git Bash) — env var di depan perintah cuma
        berlaku untuk satu perintah itu, `.env` tidak ikut tersentuh:
        ```bash
        DATABASE_URL="<connection-string-baru>" venv/Scripts/python.exe check_db.py
        ```
      - Hasil: `Connected OK.` dan `pgvector extension: ('vector', '0.8.2')`
        (atau versi terbaru yang tersedia).
      - Kalau error koneksi timeout: cek lagi apakah host-nya bertuliskan
        `-1` (Singapore), dan project sudah berstatus Active (bukan masih
        provisioning).
- [x] **Jalankan migrasi Alembic di project baru (dari kosong)**
      — concepts: orm-migrations
      - Langkah (di `backend/`):
        ```bash
        DATABASE_URL="<connection-string-baru>" venv/Scripts/python.exe -m alembic upgrade head
        ```
      - Hasil: output menunjukkan kedua revisi diterapkan berurutan
        (`9a2d76c47977` lalu `66de89f6cd67`). Ini sekaligus jadi bukti bahwa
        migrasi kita benar-benar bisa jalan dari database kosong (uji yang
        belum pernah dilakukan sebelumnya, karena DB lama sudah "dibangun
        pelan-pelan" sejak Fase 1).
      - Kalau gagal di revisi pertama karena `ImportError: pgvector`: pastikan
        `venv/Scripts/python.exe` yang dipakai (bukan Python sistem).
      - **Bug nyata ketemu di sini (2026-09-22):** gagal dengan
        `UndefinedObject: index "idx_items_created_at" does not exist`.
        Sebabnya, migrasi `9a2d76c47977` diautogenerate dulu terhadap DB
        Sydney yang MASIH menyisakan tabel `items` dari project Supabase
        sebelumnya (lihat knowledge-graph.md, `orm-migrations`) -- operasi
        `drop_index`/`drop_table` untuk tabel itu ikut ter-diff sebagai
        bagian migrasi, padahal itu cuma beres-beres lingkungan lama, bukan
        evolusi skema yang sah. Tidak ketahuan selama ini karena DB Sydney
        satu-satunya yang pernah dipakai memang sudah punya (lalu kehilangan)
        tabel itu. Baru ketahuan sekarang karena Singapore benar-benar kosong
        sejak awal. **Fix:** hapus semua baris terkait `items` dari
        `upgrade()` dan `downgrade()` di file migrasi itu -- aman dilakukan
        karena revision id-nya sudah tercatat di `alembic_version` DB lama;
        Alembic cuma mencocokkan revision id, tidak mendiff ulang isi migrasi
        yang sudah diterapkan. Diverifikasi: `alembic current` di Sydney
        (pakai `.env` lama) maupun Singapore sama-sama `66de89f6cd67 (head)`
        setelah fix.
- [x] **Tulis script salin data, `backend/migrate_to_singapore.py`**
      — concepts: relational-schema-design
      - Langkah: buat file itu berisi persis:
        ```python
        """
        Sekali pakai: salin semua baris dari project Supabase LAMA (Sydney) ke
        yang BARU (Singapore). Jalankan sekali, hapus file ini setelahnya --
        bukan bagian dari aplikasi.

        Kedua URL diberikan lewat argumen command-line, BUKAN disimpan di
        file/.env manapun -- supaya connection string project lama tidak
        tertinggal di mana-mana setelah migrasi selesai.

        Usage:
            venv/Scripts/python.exe migrate_to_singapore.py "<URL_LAMA>" "<URL_BARU>"
        """
        import sys

        from sqlalchemy import create_engine, text


        def connect(url: str):
            # Pola sama seperti database.py: skema polos "postgresql://"
            # diarahkan eksplisit ke driver psycopg (v3), bukan psycopg2.
            return create_engine(url.replace("postgresql://", "postgresql+psycopg://", 1))


        old_engine = connect(sys.argv[1])
        new_engine = connect(sys.argv[2])

        with old_engine.connect() as old, new_engine.connect() as new:
            users = old.execute(text("SELECT * FROM users")).mappings().all()
            print(f"{len(users)} users di DB lama")
            for u in users:
                new.execute(
                    text(
                        "INSERT INTO users (id, email, password_hash, created_at) "
                        "VALUES (:id, :email, :password_hash, :created_at) "
                        "ON CONFLICT (id) DO NOTHING"
                    ),
                    dict(u),
                )
            new.commit()

            items = old.execute(text("SELECT * FROM saved_items")).mappings().all()
            print(f"{len(items)} saved_items di DB lama")
            for i in items:
                # Query mentah (bukan lewat model SavedItem) mengembalikan
                # kolom embedding sebagai teks literal vektor apa adanya
                # (mis. "[0.0123,-0.045,...]"), jadi tinggal di-CAST balik.
                new.execute(
                    text(
                        "INSERT INTO saved_items "
                        "(id, user_id, url, platform, title, summary, category, "
                        " raw_content, embedding, created_at) "
                        "VALUES "
                        "(:id, :user_id, :url, :platform, :title, :summary, :category, "
                        " :raw_content, CAST(:embedding AS vector), :created_at) "
                        "ON CONFLICT (id) DO NOTHING"
                    ),
                    dict(i),
                )
            new.commit()

            old_n = old.execute(text("SELECT count(*) FROM saved_items")).scalar()
            new_n = new.execute(text("SELECT count(*) FROM saved_items")).scalar()
            ok = "OK" if old_n == new_n else "BEDA -- JANGAN LANJUT, cek manual"
            print(f"Verifikasi jumlah saved_items: lama={old_n} baru={new_n} [{ok}]")
        ```
      - Hasil: file tersimpan di `backend/migrate_to_singapore.py`.
- [x] **Jalankan migrasi data**
      - Langkah (di `backend/`):
        ```bash
        venv/Scripts/python.exe migrate_to_singapore.py "<connection-string-LAMA-Sydney>" "<connection-string-BARU-Singapore>"
        ```
      - Hasil: baris terakhir `Verifikasi jumlah saved_items: lama=N baru=N [OK]`
        dengan N sama persis. Kalau `[BEDA]`: **jangan lanjut** — DB lama
        belum disentuh sama sekali oleh script ini (cuma dibaca), jadi aman
        untuk didiagnosis ulang tanpa risiko kehilangan data.
- [x] **Verifikasi manual login + data di DB baru**
      - Langkah (di `backend/`):
        ```bash
        DATABASE_URL="<connection-string-baru>" venv/Scripts/python.exe -c "
        from database import SessionLocal; from sqlalchemy import text
        with SessionLocal() as db:
            print(db.execute(text('select count(*) from users')).scalar(), 'users')
            print(db.execute(text('select count(*), count(embedding) from saved_items')).all())
        "
        ```
      - Hasil: jumlah user dan item sama dengan yang di database lama, dan
        `count(embedding)` juga sama (bukti vektor ikut tersalin dengan benar,
        bukan cuma baris kosong).
- [x] **Ganti `backend/.env` ke database baru secara permanen**
      — concepts: api-key-secrets-management
      - Langkah: buka `backend/.env`, ganti nilai `DATABASE_URL` jadi
        connection string Singapore yang baru.
      - Hasil (di `backend/`): `venv/Scripts/python.exe check_db.py` (tanpa
        env var di depan, memakai `.env`) tetap mencetak `Connected OK.`
- [x] **Retest aplikasi lokal penuh dengan DB baru**
      - Langkah: jalankan backend (`venv/Scripts/python.exe -m uvicorn main:app --port 8000`),
        buka app di emulator/HP yang masih arah ke `10.0.2.2:8000`/localhost,
        login dengan akun uji, pastikan daftar item, pencarian, dan "Rangkum
        dengan AI" semuanya masih jalan seperti sebelumnya.
      - Hasil: semua fitur berfungsi sama seperti sebelum migrasi. Ini bukti
        migrasi tidak merusak apa pun sebelum lanjut ke commit/deploy.
      - Kalau ada yang beda: jangan lanjut ke §5.1 dulu, cari tahu dulu
        bedanya di mana (kemungkinan besar salah salin connection string).
- [x] **Hapus script migrasi & connection string lama dari mana pun**
      — concepts: api-key-secrets-management
      - Langkah: `rm backend/migrate_to_singapore.py` (di `backend/`).
        Bersihkan juga connection string lama dari clipboard/catatan
        sementara mana pun kamu menyimpannya.
      - Hasil: file tidak ada lagi (`git status` di §5.1 nanti tidak akan
        menyinggungnya sama sekali).
- [ ] **Pause (jangan hapus dulu) project Supabase lama**
      - Langkah: dashboard project **lama** (Sydney) → Settings → General →
        **Pause project**.
      - Kenapa pause, bukan langsung delete: kalau nanti ternyata ada yang
        kelewat tersalin, project lama masih bisa dibuka lagi untuk dicek.
        Hapus permanen belakangan, setelah project baru terbukti stabil
        dipakai beberapa hari (bukan bagian task fase ini).

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

**Amandemen (2026-09-22) — `.gitignore` root ketinggalan di commit pertama.**
Kejadian: `.gitignore` root sempat dibuat di disk tapi lupa di-`git add`
sebelum commit pertama, jadi `.claude/CLAUDE.md` ikut ter-track (dua commit
sudah kadung ter-push). **Bukan kebocoran secret** — dicek lewat
`git grep` di seluruh history: `.env` dan `venv/` tetap aman karena sudah
dilindungi `backend/.gitignore` yang independen dari file root. Yang bocor
cuma file instruksi proyek, tanpa credential apa pun.

Fix-nya **tidak** pakai rewrite history/force-push (itu obat untuk secret
sungguhan yang bocor) — cukup stop tracking mulai commit berikutnya:
- [ ] Ubah `.gitignore` root: baris `.claude/settings.local.json` diganti
      `.claude/` (kamu putuskan seluruh folder itu bukan bagian repo, bukan
      cuma file settings-nya)
- [ ] `git rm -r --cached .claude` lalu `git add .gitignore`
- [ ] Commit: `git commit -m "chore: add root .gitignore, stop tracking .claude/"`
- [ ] Push tanpa `--force`: `git push`
- [ ] Verifikasi di GitHub: buka repo di browser, pastikan folder `.claude`
      sudah tidak ada di halaman file (riwayat lama tetap menyimpannya, itu
      wajar dan tidak masalah karena isinya bukan secret)

### 5.2 File konfigurasi deploy

- [ ] **Tulis `backend/Dockerfile`**
      — concepts: deployment-hosting
      - Langkah: buat file `backend/Dockerfile` berisi persis:
        ```dockerfile
        # Versi Python sama dengan venv lokal (3.14) -- versi yang sudah teruji.
        FROM python:3.14-slim

        # Log langsung keluar (tanpa buffer) supaya tampil real-time di dashboard host.
        ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

        WORKDIR /app

        # requirements dulu, baru kode: layer install tidak dibangun ulang
        # setiap kali kode berubah (build lebih cepat).
        COPY requirements.txt .
        RUN pip install --no-cache-dir -r requirements.txt

        COPY . .

        # Railway otomatis inject env var PORT dan app WAJIB listen di
        # 0.0.0.0:$PORT (dikonfirmasi di docs.railway.com/variables/reference).
        # Satu worker saja: pool koneksi Supavisor free tier terbatas, dan
        # BackgroundTasks berjalan in-process.
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
        build log Railway di 5.4 jadi pengujiannya.
- [ ] **Commit & push file deploy**
      - Langkah (di `FETCH/`): `git add backend/Dockerfile backend/.dockerignore`
        → `git commit -m "Add Dockerfile for deploy"` → `git push`
      - Hasil: kedua file terlihat di GitHub.
      - Catatan: kalau kamu sudah pernah commit ini lebih dulu dengan pesan
        yang menyebut "Render" (sebelum amandemen pivot ke Railway) -- tidak
        apa-apa, Dockerfile-nya sendiri host-agnostic (cuma baca env var
        `PORT`, tidak spesifik Render). Tidak perlu commit ulang cuma buat
        ganti nama di pesan commit lama.

### 5.3 Railway: akun, service, environment variables

**Amandemen (2026-09-23) — akun Railway baru (trial di-reset), repo dijadikan
public.** Akun Railway pertama sudah kepakai trial-nya sia-sia (dicoba dari
sesi lain sebelum sempat sampai deploy). User buat akun baru + repo GitHub
diubah jadi **public** (tidak masalah dari sisi secret -- `.env` sudah
terverifikasi tidak pernah ter-track sejak Fase 5.1, jadi tidak ada yang
"bocor" cuma karena repo terbuka).

**Bug nyata ketemu & sudah di-fix (2026-09-23):** deploy pertama gagal.

- **Gejala:** log build berhenti dengan `Script start.sh not found`, lalu
  `Railpack could not determine how to build the app`.
- **Sebab:** Railway (builder-nya bernama **Railpack**) baca **root repo**,
  bukan folder `backend/` — cuma melihat folder `backend/`/`docs/`/`mobile/`
  tanpa tahu cara build-nya, karena task **"Set Root Directory ke backend"**
  di bawah belum dikerjakan waktu deploy pertama otomatis terpicu begitu
  repo di-connect.
- **Fix:** isi Root Directory dengan `backend` → Railway ketemu
  `backend/Dockerfile` dan build lewat situ.
- **Pelajaran:** kalau urutannya connect repo dulu baru atur Root Directory
  belakangan (urutan yang wajar dilakukan orang), deploy pertama **hampir
  pasti gagal** duluan. Itu normal, bukan tanda ada yang salah secara
  fundamental — tinggal redeploy setelah setting-nya benar.

- [x] **Buat akun Railway & cek TIDAK diminta kartu kredit**
      — concepts: deployment-hosting
      - Hasil: akun baru dibuat, tidak diminta kartu.
- [x] **Buat project baru dari repo GitHub (public)**
      — concepts: deployment-hosting
      - Hasil: service ter-connect ke repo `fetch`.
- [x] **Set Root Directory ke `backend`**
      — concepts: deployment-hosting
      - Hasil: field tersimpan -- ini yang memperbaiki error Railpack di atas.
- [ ] **Verifikasi build sukses setelah fix Root Directory**
      — concepts: deployment-hosting
      - Langkah: buka tab **Deployments** → deployment terbaru (atau trigger
        **Redeploy** kalau belum otomatis jalan ulang setelah ganti setting)
        → tunggu, baca log build.
      - Hasil: log build kali ini menyebut `Dockerfile` (bukan Railpack
        auto-detect lagi), diakhiri `Uvicorn running on http://0.0.0.0:...`,
        status deployment jadi **Success**/**Active**.
      - Kalau masih gagal dan log **tidak** menyebut Dockerfile sama sekali:
        buka Settings → bagian **Build** → cari opsi pilih builder secara
        eksplisit → pilih **Dockerfile** (jangan biarkan "Automatic").
- [ ] **Cek & pilih region Singapore — lakukan ini SEKARANG, bukan belakangan**
      — concepts: deployment-hosting
      - Langkah: Settings → bagian **Region** (atau saat konfigurasi
        deployment pertama) → cari **Southeast Asia (Singapore)**.
      - Hasil kalau tersedia: pilih itu, lanjut normal.
      - Hasil kalau TERKUNCI/tidak muncul (kemungkinan nyata di plan Trial/
        Free, lihat amandemen di atas): catat region default yang dipakai,
        lanjutkan deploy ke situ dulu (jangan berhenti total di sini) --
        efeknya cuma latensi DB lebih tinggi dari yang direncanakan, bukan
        kegagalan. Kabari supaya kita evaluasi ulang opsi lain kalau memang
        terkunci.
- [ ] **Buat JWT secret baru khusus production**
      — concepts: api-key-secrets-management
      - Langkah (di `backend/`):
        `venv/Scripts/python.exe -c "import secrets; print(secrets.token_urlsafe(48))"`
      - Simpan hasilnya sementara (jangan ditempel di chat, file repo, atau
        screenshot). Kenapa baru, bukan menyalin dari `.env`: secret lokal
        sudah berkali-kali tersentuh selama development; production pantas
        punya secret sendiri. Token lama dari laptop jadi tidak berlaku di
        server — memang itu tujuannya.
- [ ] **Isi environment variables di Railway**
      — concepts: api-key-secrets-management
      - Langkah: tab **Variables** di service → **New Variable** (atau "Raw
        Editor" untuk tempel sekaligus), tiga baris:

        | Key | Value |
        |---|---|
        | `DATABASE_URL` | salin persis dari `backend/.env` (host-nya `...pooler.supabase.com:5432`, region Singapore) |
        | `GEMINI_API_KEY` | salin dari `backend/.env` |
        | `JWT_SECRET_KEY` | hasil task sebelumnya |

      - Perhatikan: tanpa tanda kutip, tanpa spasi di awal/akhir. Secret
        diisi di dashboard, **bukan** di file mana pun di repo.
      - Hasil: tiga env var tersimpan. Railway menandainya sebagai
        "staged changes" -- klik **Deploy** di pojok untuk menerapkannya
        (jangan lupa, beda dari Render yang langsung apply).
- [ ] **Generate domain publik**
      — concepts: deployment-hosting
      - Langkah: Settings → **Networking** → **Public Networking** → klik
        **Generate Domain**.
      - Kenapa task terpisah: **beda dari Render, Railway TIDAK otomatis
        kasih URL publik** -- tanpa langkah ini service jalan tapi tidak
        bisa diakses dari luar sama sekali.
      - Hasil: muncul URL berbentuk `https://<nama-acak>.up.railway.app`.
        Catat URL ini, dipakai di semua task setelah ini.
- [x] **Set health check path**
      - Langkah: buka **Settings** service → cari field **Healthcheck Path**
        (dokumentasi resmi Railway cuma bilang "di halaman service settings",
        tidak menyebut nama sub-tab pastinya — kemungkinan besar ada di
        bagian **Deploy**, tapi kalau tidak ketemu di situ, scroll/cari
        seluruh halaman Settings) → isi `/health`.
      - Kenapa: Railway baru mengalihkan trafik ke versi baru setelah
        `/health` menjawab 200 — deploy yang rusak tidak menggantikan yang
        sehat. Default timeout 300 detik, cukup untuk build kita.

### 5.4 Deploy & verifikasi server

*(Build & deploy pertama sudah diverifikasi di task "Verifikasi build sukses
setelah fix Root Directory" di §5.3 — kalau paket lain (bukan Root Directory)
yang bikin build gagal: `ERROR: No matching distribution found for <paket>`
→ paket itu belum punya versi untuk Python 3.14 Linux, catat namanya;
`KeyError: 'GEMINI_API_KEY'`/`JWT_SECRET_KEY` → env var belum diisi/salah
nama, balik ke task "Isi environment variables di Railway" di §5.3.)*

- [x] **Verifikasi `/health` dari URL publik**
      — concepts: deployment-hosting
      - Langkah (Git Bash): `curl -i https://<domain-railway>/health`
      - Hasil: `HTTP/2 200` dan body `{"status":"ok"}`. Buka juga URL yang
        sama di browser HP (pakai data seluler, bukan WiFi rumah) — harus
        tampil teks yang sama.
      - **Hasil sungguhan (2026-09-23):** `https://fetch-production-35a4.up.railway.app/health`
        → `200 OK`, `{"status":"ok"}`, 0.43s. Header response `x-railway-edge: sin1`
        dan `x-hikari-trace: sin1.hs0s` mengindikasikan server jalan di
        **Singapore** — region trial ternyata tersedia. Belum dicek dari
        browser HP secara langsung, cuma dari curl laptop.
- [x] **Verifikasi migrasi database = head**
      — concepts: orm-migrations
      - Konteks: karena production memakai DB yang sama dengan dev, migrasi
        tidak perlu dijalankan lagi — tapi harus **dibuktikan**, bukan diasumsikan.
      - Langkah (di `backend/`, laptop): `venv/Scripts/python.exe -m alembic current`
      - Hasil: mencetak `66de89f6cd67 (head)`.
      - Kalau hasilnya revisi lain / kosong: `venv/Scripts/python.exe -m alembic upgrade head`,
        lalu cek ulang.
- [x] **Uji login production dengan curl**
      - Langkah (Git Bash), pakai akun uji yang sudah ada:
        ```bash
        curl -s -X POST https://<domain-railway>/auth/login \
          -H "Content-Type: application/json" \
          -d '{"email":"rag-test@example.com","password":"ragtest12345"}'
        ```
      - Hasil: JSON berisi `"access_token":"eyJ..."`. Salin nilai token itu
        (tanpa kutip) untuk task-task berikut.
      - Kalau `500`: klik deployment yang aktif di halaman service (panel
        log runtime terbuka otomatis di situ — bukan tombol "View Logs"
        terpisah; kalau butuh log waktu build, bukan runtime, klik tab
        **Build Logs** di panel yang sama) — biasanya `DATABASE_URL` salah.
      - **Hasil sungguhan (2026-09-23):** token diterima normal.
- [x] **Uji daftar item production**
      - Langkah: `curl -s https://<domain-railway>/items -H "Authorization: Bearer <token>"`
      - Hasil: JSON array berisi item-item akun uji (Rendang, Deadlift, dst.) —
        bukti server membaca database yang sama.
      - **Hasil sungguhan (2026-09-23):** array item akun `rag-test` tampil
        lengkap (Sourdough, dst.) — server production baca DB Singapore yang
        sama dengan dev.
- [x] **Uji pencarian semantik production**
      - Langkah:
        ```bash
        curl -s -w "\n%{time_total}s\n" -X POST https://<domain-railway>/search \
          -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
          -d '{"query":"olahraga angkat beban"}'
        ```
      - Hasil: hasil pertama *Deadlift*. Angka di baris terakhir = latensi
        production pertamamu (di laptop: ± 2 detik) — catat.
      - **Hasil sungguhan (2026-09-23):** hasil pertama Deadlift (score
        0.7138), lalu HIIT (0.6705) — identik dengan hasil uji lokal.
        Latensi 0.77s (dari koneksi laptop saat ini, bukan dari HP).
- [x] **Uji simpan + pengayaan AI di server**
      - Langkah:
        ```bash
        curl -s -X POST https://<domain-railway>/items \
          -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
          -d '{"url":"https://en.wikipedia.org/wiki/Gado-gado"}'
        ```
        Tunggu ± 15 detik, lalu buka panel log deployment aktif (lihat cara di task login production tadi).
      - Hasil: log berisi `enrichment - item ... diperkaya: platform=generic ... ai=True embedding=True`.
      - Kalau `ai=False` dengan `429` di log: kuota harian Gemini habis
        (dipakai bersama dengan laptop). Bukan bug deploy — coba lagi besok.
      - **Hasil sungguhan (2026-09-23):** item Gado-gado, `processed: true`,
        title "Gado-gado - Wikipedia", ringkasan Bahasa Indonesia lengkap,
        kategori "Food & Cooking". Ekstraksi + Gemini + embedding semua
        jalan penuh di production (diverifikasi lewat `GET /items/{id}`,
        bukan lewat log dashboard — hasilnya setara).
- [x] **Uji ekstraksi YouTube dari server**
      - Langkah: ulangi task sebelumnya dengan URL
        `https://www.youtube.com/watch?v=jNQXAC9IVRw`, lalu cek panel log yang sama.
      - Hasil yang mungkin — **catat mana yang terjadi**:
        - `sources=['yt_dlp']` → yt-dlp jalan normal dari server.
        - `sources=['open_graph']` + baris `yt-dlp gagal ... Sign in to confirm you're not a bot`
          → YouTube memblokir IP datacenter (umum terjadi di host cloud). Item
          tetap tersimpan dengan judul + deskripsi dari Open Graph
          (graceful degradation bekerja sesuai desain), hanya lebih tipis.
          Catat sebagai keterbatasan production, bukan kegagalan task.
      - **Hasil sungguhan (2026-09-23):** kasus kedua yang terjadi —
        `title: "YouTube"`, ringkasan generik soal platform-nya ("Platform
        tempat pengguna dapat menikmati video dan musik..."), bukan tentang
        video "Me at the zoo" itu sendiri. Ciri khas yt-dlp diblokir IP
        Railway lalu jatuh ke Open Graph generik. `processed: true`, item
        tetap tersimpan dan bisa dicari — graceful degradation bekerja
        sesuai desain. Belum sempat cek log dashboard langsung untuk
        konfirmasi baris `yt-dlp gagal` persis, tapi datanya konsisten
        dengan skenario itu.
- [ ] **Aktifkan fitur Serverless (tidur otomatis)**
      - Langkah: Settings service → cari bagian **Serverless** → aktifkan.
      - Kenapa wajib, bukan opsional: beda dari Render, di Railway ini
        **mati by default**. Tanpa ini, service menyala 24/7 dan menghabiskan
        kredit trial/bulanan jauh lebih cepat (lihat amandemen di atas,
        estimasi ± $3/bulan kalau menyala terus tanpa fitur ini).
      - Hasil: ada indikator "Serverless enabled" di dashboard.
- [ ] **Uji perilaku cold start (service tidur)**
      - Langkah: jangan sentuh server ≥ 10 menit (Railway tidur setelah ±5
        menit tanpa trafik keluar-masuk, beda dari Render yang 15 menit).
        Lalu jalankan `curl -i -w "\n%{time_total}s\n" https://<domain-railway>/health`.
      - Hasil yang mungkin — **catat mana yang terjadi**:
        - Langsung `200` setelah beberapa detik jeda (mirip pengalaman Render).
        - **Satu kali `502`**, lalu `curl` yang sama diulang langsung `200`.
          Ini perilaku terdokumentasi Railway (request pertama ke service
          yang tidur kadang gagal sekali sebelum instance-nya benar-benar
          hidup) — bukan bug, tapi catat karena app mobile kita **belum**
          menangani retry otomatis untuk kasus ini.

### 5.5 Build app untuk production

- [x] **Buat base URL API bisa diatur saat build**
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
- [x] **Commit perubahan base URL**
      - Langkah: `git add mobile/lib/api/api_client.dart` →
        `git commit -m "Configurable API base URL via dart-define"` → `git push`
- [x] **Build release APK dengan URL production**
      - Langkah (di `mobile/`, Git Bash):
        `/c/flutter/bin/flutter build apk --release --dart-define=API_BASE_URL=https://<domain-railway>`
        (tanpa garis miring `/` di akhir URL — kode menambahkan `/items` dst.
        sendiri; garis miring ganda bisa bikin 404.)
      - Hasil: `√ Built build\app\outputs\flutter-apk\app-release.apk (xx.xMB)`.
      - Catatan: APK ini ditandatangani dengan **debug key** (setting bawaan
        di `android/app/build.gradle.kts`). Cukup untuk sideload ke HP sendiri;
        baru jadi masalah kalau suatu hari mau ke Play Store.
      - **Bug lingkungan ketemu (2026-09-23, bukan bug kode):** percobaan
        pertama gagal — `An Application Control policy has blocked this
        file` waktu menjalankan `gen_snapshot.EXE` (compiler AOT Flutter
        untuk target arm64 release). Ini kebijakan Windows di laptop, bukan
        error Dart/Flutter. Kemungkinan besar karena ini **pertama kalinya**
        target `--release` dijalankan di laptop ini (semua build sebelumnya
        di proyek ini `--debug`, lewat jalur compiler berbeda). Percobaan
        kedua (tanpa perubahan apa pun) **berhasil** — sepertinya Windows
        Defender masih scan file itu di percobaan pertama. Kalau ini
        terulang lagi nanti: coba ulang 1-2x dulu sebelum curiga ada yang
        salah beneran.
      - **Hasil sungguhan (2026-09-23):** `app-release.apk`, 48.0MB, build
        ke-2 sukses, dengan `API_BASE_URL=https://fetch-production-35a4.up.railway.app`.

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
      - Langkah: jangan buka Fetch ≥ 10 menit (Railway) → share satu link.
      - Hasil: tetap tersimpan, tapi bisa tertahan beberapa detik-menit
        (server Railway sedang bangun dari mode Serverless), atau sheet
        "Saved" sempat menampilkan pesan gagal sekali (kalau kena 502 di
        request pertama, lihat §5.4) — coba share ulang kalau itu terjadi.
        Catat pengalamanmu: masih bisa diterima, atau perlu ditangani nanti
        (mis. retry otomatis di app, atau matikan Serverless kalau
        kreditnya masih cukup)?
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
        "Deployment": host & region (Railway, region yang ternyata
        terpakai -- Singapore kalau tersedia di §5.3), latensi `/search` dari
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

- [x] Tambahkan filter kategori pada query pencarian
      — concepts: hybrid-retrieval
- [x] Tambahkan filter rentang waktu (`created_at`) pada query pencarian
      — concepts: hybrid-retrieval
- [x] Gabungkan filter terstruktur dan similarity dalam satu query SQL
      — concepts: hybrid-retrieval
      - `SearchFilters` (schemas.py) = `category`, `created_after` (inklusif),
        `created_before` (eksklusif); dipakai `/search` dan `/search/answer`.
        Filter masuk WHERE yang sama dengan `distance <= 1 - MIN_SCORE`,
        bukan disaring di Python setelah LIMIT.
- [x] Uji query campuran (semantik + filter) memberi hasil yang masuk akal
      — concepts: hybrid-retrieval
      - **Hasil sungguhan (2026-09-24, akun rag-test):** "makanan indonesia"
        tanpa filter → Rendang, Gado-gado, Nasi goreng. `created_after`
        2026-09-22 → cuma Gado-gado (disimpan 09-23). `created_before`
        2026-09-22 → Rendang + Nasi goreng. `category: Travel` → kosong
        (benar). "tempat wisata gunung" + Travel → Mount Bromo (0.73).
        Kategori di luar daftar / rentang terbalik → 422.
      - Temuan: "liburan" + Travel → kosong, padahal Bali/Bromo ada. Bukan
        bug filter: skor keduanya < MIN_SCORE 0.60 untuk query satu kata
        (tanpa filter pun hasilnya cuma HIIT 0.607). Filter hanya
        menyaring, tidak menurunkan ambang.

- [x] Endpoint `PATCH /items/{id}` untuk edit
      - Field opsional title / summary / category (kategori divalidasi ke
        daftar tetap). Title & kategori tidak boleh dikosongkan, summary boleh.
        409 kalau item masih diproses AI (hasil AI akan menimpa editan).
        Title/summary berubah → embedding dibuat ulang (kalau Gemini gagal,
        vektor lama dipertahankan). Plus `GET /items/categories` untuk
        dropdown di app.
      - Bug ketemu saat uji: judul `"   "` lolos `min_length=1` karena strip
        jalan SETELAH validasi panjang → diperbaiki dengan validator
        `mode="before"`.
- [x] UI edit item di Flutter
      - Menu ⋮ di tiap item → Edit → bottom sheet (judul, ringkasan,
        dropdown kategori). Hanya field yang berubah yang dikirim.
- [x] UI hapus item di Flutter
      - Menu ⋮ → Hapus → dialog konfirmasi → item hilang dari list tanpa
        muat ulang semua.
- [x] Screen browse berdasarkan kategori
      - Chip kategori di atas daftar home (hanya kategori yang dipakai, urut
        jumlah item). Pencarian punya filter kategori + waktu simpan
        (7/30/365 hari) yang dikirim ke hybrid search di backend.
- [x] Loading state di semua screen yang memanggil API
- [x] Error handling dan tombol retry di API client
      - `ApiClient._send`: timeout 30 detik, ulang otomatis SEKALI untuk
        gangguan sementara (offline, timeout, 502/503/504 — kasus Railway
        bangun tidur di §5.4). POST /items dan register TIDAK diulang
        otomatis (bisa dobel); UI memberi tombol "Coba lagi". Error jaringan
        jadi `ApiException(0, ...)`.
      - Home: gagal muat pertama → layar error + "Coba lagi"; gagal refresh
        saat data sudah ada → snackbar, data lama tetap tampil; 401 →
        "Sesi sudah berakhir" + "Masuk lagi". Share-sheet yang gagal / belum
        login sekarang memberi snackbar (dulu cuma debugPrint, diam-diam).
- [x] Empty state saat belum ada item tersimpan
      - Juga: "Tidak ada yang cocok dengan filter ini" + "Cari tanpa filter".
- [x] Uji semua alur di emulator (2026-09-24, backend lokal + DB production)
      - Sesi kedaluwarsa (token lama beda secret) → layar "Sesi sudah
        berakhir" → login → chip kategori → filter Travel → edit judul item
        YouTube jadi "Me at the zoo" → cari + filter waktu & kategori →
        simpan link baru (Tempeh) → hapus → matikan server + tarik refresh
        → snackbar "Tidak bisa terhubung", data tetap tampil. Semua sesuai.
- [ ] **Deploy backend Fase 6 ke Railway** — APK baru memanggil
      `PATCH /items/{id}`, `GET /items/categories`, dan filter di `/search`;
      server production yang lama belum punya ketiganya (edit & filter
      kategori di app akan gagal sampai backend ter-deploy). Tidak ada
      migrasi DB.
