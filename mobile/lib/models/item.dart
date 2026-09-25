/// Mirror of the backend's `ItemPublic` schema (backend/schemas.py).
/// Every field except `id`, `url`, `createdAt` is nullable -- the same
/// nullability decision as in docs/data-model.md, because those fields are
/// AI enrichment results that may not have finished processing yet.
class Item {
  final String id;
  final String url;
  final String? platform;
  final String? title;
  final String? summary;
  final String? category;

  /// False while the backend is still extracting metadata + calling Gemini
  /// (runs in the background after POST /items, see backend/enrichment.py).
  final bool processed;

  /// False = the backend couldn't read the link's content at all. Separates
  /// "link unreadable" from "AI failed to summarise" when [summary] is null.
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
        // Defaults to false: an older backend (without this field) still
        // shows the "couldn't read" message as before.
        hasContent: json['has_content'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// The title shown in the UI. The title is filled in by the AI (or from
  /// extraction) in the background; until then, or if the content really
  /// can't be read (e.g. a private post), show the URL.
  String get displayTitle => title?.isNotEmpty == true ? title! : url;
}

/// One result from POST /search: item + similarity score (cosine similarity).
/// The score is only meaningful for comparing results within the same
/// search, not an absolute relevance percentage (see backend/routers/search.py).
class SearchResult {
  final Item item;
  final double score;

  SearchResult({required this.item, required this.score});

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        item: Item.fromJson(json),
        score: (json['score'] as num).toDouble(),
      );
}
