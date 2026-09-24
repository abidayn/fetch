/// Cermin dari schema `ItemPublic` di backend (backend/schemas.py).
/// Semua field selain `id`, `url`, `createdAt` nullable -- ikut keputusan
/// nullable yang sama seperti di docs/data-model.md, karena field itu hasil
/// pengayaan AI yang belum tentu sudah selesai diproses.
class Item {
  final String id;
  final String url;
  final String? platform;
  final String? title;
  final String? summary;
  final String? category;

  /// False selama backend masih mengekstrak metadata + memanggil Gemini
  /// (jalan di background setelah POST /items, lihat backend/enrichment.py).
  final bool processed;

  /// False = backend tidak bisa membaca isi link sama sekali. Membedakan
  /// "link tidak terbaca" dari "AI gagal merangkum" saat [summary] null.
  final bool hasContent;
  final DateTime createdAt;

  Item({
    required this.id,
    required this.url,
    this.platform,
    this.title,
    this.summary,
    this.category,
    required this.processed,
    required this.hasContent,
    required this.createdAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        url: json['url'] as String,
        platform: json['platform'] as String?,
        title: json['title'] as String?,
        summary: json['summary'] as String?,
        category: json['category'] as String?,
        processed: json['processed'] as bool? ?? true,
        // Default false: backend lama (belum punya field ini) tetap
        // menampilkan pesan "tidak terbaca" seperti sebelumnya.
        hasContent: json['has_content'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// Judul yang ditampilkan di UI. Title diisi AI (atau hasil ekstraksi) di
  /// background; selama belum ada, atau kalau kontennya memang tidak bisa
  /// dibaca (mis. Instagram tanpa login), tampilkan URL-nya.
  String get displayTitle => title?.isNotEmpty == true ? title! : url;
}

/// Satu hasil dari POST /search: item + skor kemiripan (cosine similarity).
/// Skor cuma bermakna untuk membandingkan hasil dalam satu pencarian yang
/// sama, bukan persentase relevansi absolut (lihat backend/routers/search.py).
class SearchResult {
  final Item item;
  final double score;

  SearchResult({required this.item, required this.score});

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        item: Item.fromJson(json),
        score: (json['score'] as num).toDouble(),
      );
}
