# Knowledge Graph

Glosarium ringan konsep yang tersentuh di proyek ini — bukan gerbang yang
memblokir progres. Satu section per konsep, namanya cocok dengan tag
`concepts:` di plan.md.

**Sejak 2026-09-17:** status disederhanakan jadi `not-started` / `touched` /
`explained`. Entry lama (introduced/practicing/understood + evidence log)
dibiarkan apa adanya sebagai riwayat — tidak diubah retroaktif, cuma tidak
dipakai lagi untuk entry baru. Gunanya file ini sekarang: referensi cepat
"topik apa saja yang saya sentuh di proyek ini", berguna buat persiapan
interview atau nyari yang perlu di-brush-up, bukan buat gerbang sebelum lanjut
kerja.

depends-on tetap dicatat buat konteks urutan belajar yang masuk akal, tapi
bukan lagi syarat keras sebelum mulai.

---

## relational-schema-design
- status: introduced
- depends-on: none
- introduced: 2026-09-02
- last-reviewed: 2026-09-02
- evidence:
  - 2026-09-02 · "Desain skema users + saved_items + FK + dimensi embedding" ·
    no questions · introduced

## orm-migrations
- status: introduced
- depends-on: relational-schema-design
- introduced: 2026-09-02
- last-reviewed: 2026-09-02
- evidence:
  - 2026-09-02 · "Model SQLAlchemy + init Alembic" · tanya beda engine vs
    session, kenapa `import models` yang tampak tak terpakai itu wajib, dan
    kenapa dua cascade dipasang sekaligus → semua terjawab · introduced
    (catatan: 2 task generate/jalankan migrasi masih blokir DATABASE_URL)
- note (2026-09-17): migrasi pertama digenerate & di-apply sungguhan ke Supabase
  (bukan cuma tertulis). Ketemu 1 bug nyata: autogenerate lupa `import
  pgvector.sqlalchemy` di file migrasi -> NameError kalau tidak diperbaiki
  manual. Ketemu juga DB lama (project Supabase sebelumnya) yang masih
  berisi tabel `items` beda skema, sengaja di-drop atas konfirmasi user.
- note (2026-09-22): drop tabel `items` di atas ternyata ikut TERCATAT di
  migrasi `9a2d76c47977` sebagai `op.drop_index`/`op.drop_table` -- bukan
  bagian sah evolusi skema, cuma kebetulan ikut ter-diff karena autogenerate
  dijalankan waktu DB Sydney masih kotor. Baru ketahuan waktu migrasi Fase 5
  ke project Supabase Singapore yang benar-benar kosong: gagal dengan
  `UndefinedObject: index "idx_items_created_at" does not exist`. Pelajaran:
  autogenerate mendiff terhadap STATE DATABASE saat itu, bukan terhadap
  "riwayat skema yang seharusnya" -- kalau DB pembanding kotor, hasil diffnya
  ikut kotor, dan itu baru kelihatan saat migrasi dijalankan ke instalasi
  fresh yang lain. Fix: hapus operasi terkait `items` dari file migrasi (aman
  -- Alembic tidak mendiff ulang isi migrasi yang revision id-nya sudah
  tercatat di database manapun, cuma mencocokkan id).

## jwt-auth
- status: introduced
- depends-on: none
- introduced: 2026-09-02
- last-reviewed: 2026-09-02
- evidence:
  - 2026-09-02 · "Hashing password + buat/verifikasi JWT" · no questions ·
    introduced (diverifikasi langsung: salt bikin hash beda, token diubah &
    token bersecret lain ditolak, token kedaluwarsa ditolak)
- note (2026-09-17): register/login/me diuji end-to-end sungguhan lewat
  server jalan (bukan cuma unit test tanpa DB): 201/409/200/401 semua sesuai.

## middleware
- status: touched
- depends-on: jwt-auth
- note: `deps.py` -> get_current_user, dependency FastAPI (bukan middleware asli) yg baca header Authorization, dipasang di /auth/me. Diverifikasi tanpa DB: no token/token rusak/skema salah/kedaluwarsa -> semua 401.


## rest-api-design
- status: touched
- depends-on: orm-migrations
- note: routers/auth.py + routers/items.py. Pola dipakai: response_model buat nyaring output (password_hash gak pernah bocor), 401 seragam biar gak bisa dipakai enumerasi, 404 (bukan 403) buat item punya user lain, 409 buat email bentrok, 201 buat create.
- note (2026-09-17): full end-to-end lewat server jalan sungguhan ke Supabase
  -- semua 11 skenario (create/list/get/delete + kode error yg tepat) lolos.


## flutter-app-structure
- status: touched
- depends-on: none
- note: main.dart (root + routing manual via Navigator, tanpa router library),
  screens/login_screen.dart, register_screen.dart, home_screen.dart. Pola:
  GlobalKey<HomeScreenState> dioper lewat constructor (bukan state mgmt
  library) biar main.dart bisa refresh() home dari luar waktu share masuk.

## http-client-integration
- status: touched
- depends-on: flutter-app-structure, rest-api-design
- note: api/api_client.dart (satu class utk semua HTTP call + header auth
  otomatis) + api/token_storage.dart (flutter_secure_storage, bukan
  SharedPreferences -- butuh enkripsi OS-level utk data sensitif kayak JWT).
  Ketemu hal spesifik-Android: emulator butuh base URL 10.0.2.2, bukan
  localhost/127.0.0.1 (localhost di emulator nunjuk ke emulator itu sendiri).
- note (2026-09-21): sheet "Saved" (save_result_sheet.dart) polling GET
  /items/{id} sampai `processed`. Share datang dari callback plugin tanpa
  BuildContext -> pakai GlobalKey<NavigatorState> di MaterialApp; saat cold
  start ditunggu sampai Navigator siap. url_launcher mode externalApplication
  + `<queries>` VIEW https (package visibility Android 11+).

## share-intent-integration
- status: touched
- depends-on: flutter-app-structure
- note: package receive_sharing_intent -- getInitialMedia() utk cold start,
  getMediaStream() utk warm, reset() wajib dipanggil biar link yg sama gak
  kebaca ulang tiap app dibuka. AndroidManifest: intent-filter SEND text/*,
  launchMode diganti ke singleTask (semula singleTop, salah). Ketemu bug
  terpisah pas ngerjain ini: INTERNET permission ternyata cuma ada di
  debug/AndroidManifest.xml, gak ada di manifest utama -- APK release
  bakal gagal akses internet kalau gak ditambah manual.
- note (2026-09-18): diuji sungguhan di emulator via adb + share-sheet Chrome
  asli (bukan simulasi). Warm-share: 3/4 sukses, 1 gagal tepat sesudah OS-level
  force-kill (kemungkinan besar artefak debug, bukan bug produk). Cold-share:
  data KESIMPAN benar (POST /items 201 terverifikasi) tapi ketemu bug nyata --
  splash Android macet permanen kalau app di-cold-launch lewat ACTION_SEND
  (beda dari ACTION_MAIN yang normal). Dibuktikan lewat `flutter attach` +
  hot restart (Dart isolate sehat, restart 1.2 detik) dan lewat relaunch
  normal (semua item langsung muncul).
- note (2026-09-18, lanjutan): root cause & fix ditemukan sama hari itu juga.
  Mekanisme auto-dismiss splash implisit Flutter (deteksi first-frame) tidak
  konsisten terpicu kalau Activity dibuat lewat trampoline chooser Android,
  beda dari tap launcher biasa. Fix: pasang `androidx.core:core-splashscreen`,
  panggil `installSplashScreen()` eksplisit di `MainActivity.onCreate()`
  sebelum `super.onCreate()`, ganti `LaunchTheme` extend `Theme.SplashScreen`
  (light + night). Ini kasih sinyal dismiss yang terikat ke draw-pertama
  Activity di level Android, bukan ke deteksi Flutter yang tidak reliable itu.
  Diuji ulang 2x cold-start-via-share bersih berturut-turut, dua-duanya
  sukses sempurna. BLOKIR-D di plan.md ditutup.

## web-scraping-content-extraction
- status: touched
- depends-on: none
- note: backend/extraction.py. Satu fungsi `extract(url)` yang tidak pernah
  melempar exception -- kegagalan berujung data tipis, bukan item gagal.
  Per platform: YouTube via yt-dlp (deskripsi lengkap), TikTok via oEmbed
  publik (caption), Instagram cuma Open Graph (oEmbed IG butuh token
  Facebook), generic via Open Graph + fallback paragraf awal. Pelajaran dari
  uji URL sungguhan: platform yang butuh login mengirim judul generik
  ("TikTok - Make Your Day", "Instagram") yang harus dibuang, dan banyak
  artikel (Wikipedia) tidak punya meta description sama sekali.

## llm-prompting
- status: touched
- depends-on: web-scraping-content-extraction
- note: backend/classifier.py. `response_schema` pakai model Pydantic dengan
  kategori `Literal[...]` (daftar tetap, bukan teks bebas, supaya satu topik
  tidak pecah jadi banyak label). temperature 0.2 demi konsistensi. Konten
  kosong -> Gemini tidak dipanggil sama sekali (mencegah halusinasi dari URL
  doang). Gagal/timeout -> return None, tidak melempar. Retry 3x + backoff
  untuk 429/5xx setelah 503 "high demand" benar-benar terjadi saat uji.
  Dijalankan di background (FastAPI BackgroundTasks) setelah POST /items
  membalas, jadi simpan link tidak menunggu Gemini.

## embeddings-vector-representation
- status: touched
- depends-on: llm-prompting
- note (2026-09-19): backend/embeddings.py, model gemini-embedding-2 @768 dim
  (bukan -001: lebih tegas + sudah ternormalisasi). Yang di-embed: title +
  summary. Dibuat di enrichment.py, backfill_embeddings.py untuk item lama.
  Jebakan nyata: list[str] -> SATU vektor gabungan di model ini (harus dibungkus
  Content per teks); task_type diabaikan. Penjelasan dari nol: docs/rag-guide.md §3, §5, §6.

## vector-similarity-search
- status: touched
- depends-on: embeddings-vector-representation, relational-schema-design
- note (2026-09-19): operator cosine `<=>` (3 operator mengurutkan identik pada
  vektor ternormalisasi, L2² = 2·cos_dist). Index HNSW vector_cosine_ops
  (migrasi 66de89f6cd67). Di 25 baris planner tetap Seq Scan (benar). Benchmark
  10k vektor: 80.9ms -> 1.4ms, recall@10 98%; data acak seragam cuma 32%.
  Filter user_id + HNSW butuh hnsw.iterative_scan. docs/rag-guide.md §4, §7.

## hybrid-retrieval
- status: not-started
- depends-on: vector-similarity-search, relational-schema-design
- introduced: -
- last-reviewed: -
- evidence:

## rag-pipeline
- status: touched
- depends-on: vector-similarity-search, llm-prompting
- note (2026-09-19): baru bagian R (retrieval) -- routers/search.py, POST
  /search. Ambang dua lapis (MIN_SCORE 0.60 + MAX_GAP_FROM_TOP 0.06) karena
  skor absolut tidak bisa dipercaya sendirian (teks acak dapat 0.61). Bagian
  A+G (jawaban naratif) masih stretch, cara kerjanya di docs/rag-guide.md §8-§10.
- note (2026-09-19, lanjutan): A+G dibangun -- POST /search/answer, answerer.py.
  Tidak ada hasil retrieval -> Gemini tidak dipanggil. Grounding + sitasi [n]
  yang divalidasi regex + item dibungkus <item> sebagai pertahanan prompt
  injection (diuji dengan item jebakan: tidak tembus). Model lite terpisah dari
  classifier karena kuota per model (3.6-flash: 20/hari) dan latensi (3.5-flash
  12-37s vs 3.1-flash-lite ~5s). docs/rag-guide.md §10.

## api-key-secrets-management
- status: not-started
- depends-on: none
- introduced: -
- last-reviewed: -
- evidence:

## deployment-hosting
- status: not-started
- depends-on: rest-api-design, api-key-secrets-management
- introduced: -
- last-reviewed: -
- evidence:
