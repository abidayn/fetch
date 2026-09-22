# Fetch — Data Model

Hasil desain skema database (Fase 1). Dokumen ini sumber kebenaran untuk struktur
tabel; SQLAlchemy model dan migrasi Alembic dibuat **mengikuti** dokumen ini,
bukan sebaliknya.

DDL di bawah ditulis sebagai SQL agar presisi. Implementasi sebenarnya nanti lewat
SQLAlchemy, tapi hasil akhirnya harus setara dengan ini.

---

## Tabel `users`

```sql
CREATE TABLE users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT        NOT NULL UNIQUE,
    password_hash TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

| Kolom | Keputusan | Alasan |
|---|---|---|
| `id` | `UUID`, bukan `BIGSERIAL` | ID muncul di URL API (`GET /items/{id}`). Integer berurutan bisa ditebak/di-enumerasi orang lain dan membocorkan jumlah data. UUID juga tidak butuh koordinasi kalau data pernah digabung antar environment. Konsekuensi: lebih repot dibaca manual waktu debugging — `BIGSERIAL` sebenarnya pilihan yang sah juga. |
| `email` | `TEXT`, bukan `VARCHAR(255)` | Di PostgreSQL, `TEXT` dan `VARCHAR` performanya identik — `VARCHAR(n)` cuma menambah pengecekan panjang. Batas panjang yang dikarang sendiri justru sumber bug (ada email yang sah tapi panjang). Ini spesifik Postgres; di MySQL sarannya beda. |
| `email` | `UNIQUE` | Email adalah identitas login. Kalau boleh duplikat, query login jadi ambigu — dua baris cocok, harus pilih yang mana? Constraint ini yang membuat login deterministik. |
| `email` | disimpan **lowercase** (dinormalisasi di aplikasi) | `A@x.com` dan `a@x.com` pada praktiknya orang yang sama, tapi bagi `UNIQUE` itu dua nilai berbeda. Normalisasi sebelum simpan mencegah user tidak sengaja punya dua akun. |
| `password_hash` | `TEXT NOT NULL`, bukan `CHAR(60)` | Panjang hash bergantung algoritma (bcrypt 60 karakter, argon2 beda lagi). Mengunci panjangnya membuat ganti algoritma jadi butuh migrasi. Nama kolomnya sengaja `password_hash`, bukan `password` — nama itu sendiri jadi dokumentasi bahwa kolom ini haram diisi password mentah. |
| `created_at` | `TIMESTAMPTZ`, bukan `TIMESTAMP` | `TIMESTAMPTZ` menyimpan titik waktu absolut (dinormalisasi ke UTC). `TIMESTAMP` polos menyimpan angka jam tanpa zona — ambigu begitu server jalan di UTC sementara kamu di WIB. Di Postgres, default-nya selalu `TIMESTAMPTZ`. |

---

## Tabel `saved_items`

```sql
CREATE TABLE saved_items (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    url         TEXT        NOT NULL,
    platform    TEXT        NULL,

    title       TEXT        NULL,
    summary     TEXT        NULL,
    category    TEXT        NULL,
    raw_content TEXT        NULL,

    embedding   VECTOR(768) NULL,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_saved_items_user_id ON saved_items(user_id);
```

### Yang `NOT NULL` dan yang boleh `NULL` — ini keputusan paling penting di sini

Hanya **tiga** kolom yang wajib ada saat baris dibuat: `id`, `user_id`, `url`.
Sisanya boleh kosong, dan itu disengaja.

Alasannya: `url` adalah satu-satunya hal yang benar-benar kita punya pada detik
user menekan "share". Semua kolom lain — `title`, `summary`, `category`,
`raw_content`, `embedding` — adalah hasil **pengayaan** (enrichment) yang terjadi
setelahnya: scraping metadata, panggilan Gemini, pembuatan embedding.

Kalau kolom-kolom itu dibuat `NOT NULL`, konsekuensinya fatal: **Gemini down =
user tidak bisa menyimpan link sama sekali.** Padahal menyimpan link itu inti
produknya; klasifikasi cuma nilai tambah. Dengan nullable, alurnya jadi:

1. Simpan baris dengan `url` saja → user langsung dapat konfirmasi tersimpan
2. Pengayaan jalan setelahnya (bisa gagal, bisa diulang nanti)

Ini juga yang membuat Fase 1 bisa jalan sebelum Fase 3 ada: di Fase 1, item
tersimpan dengan `title` manual dan sisanya `NULL`. Tidak perlu ubah skema waktu
AI ditambahkan nanti.

Efek samping yang menguntungkan: **kolom `NULL` sekaligus jadi penanda antrian
kerja.** Item yang butuh diklasifikasi ulang = `WHERE summary IS NULL`. Item yang
butuh di-backfill embedding = `WHERE embedding IS NULL`. Jadi kita tidak perlu
kolom status/flag terpisah — informasinya sudah terkandung di data itu sendiri.

**Konvensi tambahan (Fase 3): `raw_content` sebagai status pengayaan.**

| `raw_content` | Arti |
|---|---|
| `NULL` | Belum diproses (baru disimpan, atau server mati saat background task jalan) |
| `''` (string kosong) | Sudah diproses, tapi tidak ada isi yang bisa diambil (mis. Instagram tanpa login, URL 404) |
| berisi teks | Sudah diproses |

Pembedaan `NULL` vs `''` ini yang memungkinkan app menampilkan "memproses"
hanya untuk item yang memang masih antri, bukan selamanya untuk item yang
kontennya tidak bisa dibaca. API mengekspos ini sebagai `processed: bool`
(property di model, bukan kolom). `backfill_enrichment.py` memproses ulang
`raw_content IS NULL` dan `summary IS NULL AND raw_content != ''` (punya isi
tapi Gemini gagal), dan sengaja melewati `''`.

### Per kolom

| Kolom | Keputusan | Alasan |
|---|---|---|
| `user_id` | `NOT NULL` + foreign key | Item tanpa pemilik tidak punya arti di aplikasi ini. FK memastikan tidak mungkin ada item yang menunjuk user yang tidak ada. |
| `ON DELETE CASCADE` | hapus user → item ikut terhapus | Alternatifnya `RESTRICT` (tolak hapus user selama masih punya item) atau `SET NULL` (item jadi yatim). Untuk aplikasi personal, CASCADE yang benar: hapus akun artinya hapus datanya. |
| `url` | `NOT NULL` | Satu-satunya data yang pasti ada saat simpan. Tanpa ini barisnya tidak ada gunanya. |
| `platform` | `NULL` | Diisi hasil deteksi di Fase 3 (`youtube`/`tiktok`/`instagram`/`generic`). Sebelum Fase 3 ada, kosong. |
| `title` | `NULL` | Fase 1 diisi manual, Fase 3 diganti hasil AI, dan bisa gagal. |
| `summary`, `category` | `NULL` | Murni hasil Gemini. Kosong = belum/gagal diproses. |
| `raw_content` | `NULL` | Teks mentah hasil ekstraksi, **disimpan sengaja** meski sudah ada `summary`. Alasannya: kalau nanti prompt atau model diperbaiki, klasifikasi bisa diulang dari data ini **tanpa scraping ulang** — dan scraping itu rapuh (halaman berubah, kena rate limit, konten dihapus). Ini asuransi murah. |
| `embedding` | `VECTOR(768) NULL` | Dibahas di bawah. |
| `created_at` | `NOT NULL DEFAULT now()` | Waktu simpan, dipakai untuk urutan tampilan dan (nanti di Fase 6) filter rentang waktu pada hybrid search. |
| index `user_id` | ditambahkan | Query paling sering di aplikasi ini adalah "semua item milik user X". Tanpa index, Postgres memindai seluruh tabel tiap kali. Foreign key **tidak** otomatis membuat index di Postgres — ini kesalahpahaman umum. |

---

## Relasi

```
users (1) ──────< (banyak) saved_items
        id              user_id
```

Satu user punya banyak saved item; satu saved item milik tepat satu user.
Relasi one-to-many biasa, diwujudkan lewat kolom FK di sisi "banyak".

MVP ini single-user, tapi tabel `users` tetap ada sejak awal — karena JWT auth
(Fase 1) butuh sesuatu untuk mengidentifikasi pemilik token, dan menambahkan
konsep kepemilikan setelah ada data jauh lebih mahal daripada menyiapkannya
sekarang.

---

## Dimensi kolom `embedding`: **768**

Ini keputusan yang tidak bisa diubah dengan mudah, jadi ditulis alasannya lengkap.

**Batasannya:**
- Model `gemini-embedding-001` menghasilkan **3072** dimensi secara default, tapi
  mendukung pemotongan ke **1536** atau **768** lewat parameter
  `output_dimensionality`.
- Index pgvector (HNSW maupun IVFFlat) **hanya mendukung sampai 2000 dimensi.**

Artinya kalau kita pakai 3072, kolom `embedding` **tidak bisa diberi index sama
sekali** — setiap pencarian harus memindai seluruh tabel. Padahal di plan.md Fase
4 ada task "Buat index HNSW di kolom embedding"; task itu mustahil dikerjakan pada
3072.

**Kenapa 768 dan bukan 1536:**
- Yang di-embed adalah ringkasan pendek, bukan dokumen panjang. Selisih kualitas
  pencarian antara 768 dan 3072 kecil untuk kasus seperti ini.
- Ukuran penyimpanan 4× lebih kecil: 3072 dim × 4 byte ≈ 12 KB per item, versus
  ≈ 3 KB pada 768. Relevan karena free tier database cuma 0,5 GB.
- Query lebih cepat karena vektor yang dibandingkan lebih pendek.

**Yang rusak kalau model embedding diganti nanti:**

Dimensi ini terkunci di skema (`VECTOR(768)`). Kalau suatu saat pindah model:

1. Ganti dimensi butuh **migrasi skema** — bukan sekadar ganti konfigurasi.
2. Seluruh embedding lama harus **dibuat ulang**. Vektor dari model berbeda
   berada di "ruang" yang berbeda — membandingkannya menghasilkan angka yang
   secara matematis valid tapi **tidak bermakna**. Ini bahaya senyap: tidak ada
   error, hasil pencariannya saja yang jadi ngawur.
3. Ini berlaku bahkan kalau dimensinya kebetulan sama. Kesamaan jumlah dimensi
   tidak membuat dua model bisa dibandingkan.

**Amandemen Fase 4 (2026-09-19): model yang dipakai `gemini-embedding-2`,
bukan `gemini-embedding-001`.** Batas dimensinya sama (3072 default, dipotong ke
768), jadi skema tidak berubah. Alasan pindah (diuji langsung): lebih tegas
membedakan relevan vs tidak, dan vektornya sudah ternormalisasi. Detail di
`docs/rag-guide.md` §3.3.

Konsekuensi praktis: model embedding harus dipilih sekali dan dipertahankan.
Kalau berubah, konsekuensinya re-embed semua data — itulah kenapa `raw_content`
disimpan.

---

## Keputusan yang sengaja ditunda

| Hal | Status | Alasan |
|---|---|---|
| `UNIQUE (user_id, url)` | **tidak dipakai di MVP** | Mencegah simpan ganda, tapi memaksa `POST /items` menangani konflik, dan memblokir user yang memang sengaja menyimpan ulang. Ditinjau lagi kalau duplikat terbukti mengganggu. |
| `updated_at` / `enriched_at` | **tidak dipakai** | Informasinya sudah bisa diturunkan dari `summary IS NULL` / `embedding IS NULL`. Jangan tambah kolom yang isinya bisa dihitung dari kolom lain. |
| Tabel `categories` terpisah | **tidak dipakai** | `category` cukup jadi TEXT dulu. Normalisasi ke tabel sendiri baru masuk akal kalau kategori butuh atribut sendiri (warna, ikon, urutan). |
| Index HNSW pada `embedding` | **dibuat di Fase 4** | `idx_saved_items_embedding_hnsw`, `vector_cosine_ops` (migrasi `66de89f6cd67`). Operator class harus cocok dengan operator query (`<=>`). Hasil perbandingan sebelum/sesudah: `docs/rag-guide.md` §7. |
