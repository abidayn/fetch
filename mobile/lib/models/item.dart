/// Mirror of the backend's `ItemPublic` schema (backend/schemas.py).
/// Every field except `id`, `url`, `createdAt` is nullable -- the same
/// nullability decision as in docs/data-model.md, because those fields are
/// AI enrichment results that may not have finished processing yet.
class Item {
  final String id;
  final String url;
  final String? platform;

  /// Channel, account or site name from extraction (item detail screen).
  final String? author;
  final String? title;
  final String? summary;

  /// The AI's fixed category. No longer shown in the app (folders replaced
  /// it in the UI); kept because the backend still sends it.
  final String? category;

  /// Who wrote title/summary: a model id like 'gemini:…', 'user' (edited in
  /// the app), or null. Drives "Written by AI" vs "Edited by you".
  final String? classifiedBy;

  /// False while the backend is still extracting metadata + calling Gemini
  /// (runs in the background after POST /items, see backend/enrichment.py).
  final bool processed;

  /// False = the backend couldn't read the link's content at all. Separates
  /// "link unreadable" from "AI failed to summarise" when [summary] is null.
  final bool hasContent;

  /// The user's folder. null = Unsorted.
  final String? folderId;
  final String? folderName;

  /// Who decides the folder: 'user' (picked, or left in Unsorted on
  /// purpose), 'ai' (Fetch picks), or null (nobody decided yet). See
  /// docs/data-model.md, "Folders: who decides".
  final String? folderBy;

  /// The AI's proposed folder name (an existing folder or a new one).
  final String? folderSuggestion;
  final DateTime createdAt;

  Item({
    required this.id,
    required this.url,
    this.platform,
    this.author,
    this.title,
    this.summary,
    this.category,
    this.classifiedBy,
    required this.processed,
    required this.hasContent,
    this.folderId,
    this.folderName,
    this.folderBy,
    this.folderSuggestion,
    required this.createdAt,
  });

  /// Fetch was asked to pick and hasn't filed it yet.
  bool get waitingForAi => folderBy == 'ai' && folderId == null;

  /// Fetch proposed a folder that doesn't exist yet: it waits for the user
  /// to accept ("Create 'X'") or pick another (backend: folders.py).
  bool get suggestionWaiting => processed && waitingForAi && folderSuggestion != null;

  bool get editedByUser => classifiedBy == 'user';

  /// A copy with a different folder -- for showing a choice immediately,
  /// before the backend has confirmed it.
  Item withFolder({String? folderId, String? folderName, String? folderBy}) => Item(
        id: id,
        url: url,
        platform: platform,
        author: author,
        title: title,
        summary: summary,
        category: category,
        classifiedBy: classifiedBy,
        processed: processed,
        hasContent: hasContent,
        folderId: folderId,
        folderName: folderName,
        folderBy: folderBy,
        folderSuggestion: folderSuggestion,
        createdAt: createdAt,
      );

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        url: json['url'] as String,
        platform: json['platform'] as String?,
        author: json['author'] as String?,
        title: json['title'] as String?,
        summary: json['summary'] as String?,
        category: json['category'] as String?,
        classifiedBy: json['classified_by'] as String?,
        processed: json['processed'] as bool? ?? true,
        // Defaults to false: an older backend (without this field) still
        // shows the "couldn't read" message as before.
        hasContent: json['has_content'] as bool? ?? false,
        folderId: json['folder_id'] as String?,
        folderName: json['folder_name'] as String?,
        folderBy: json['folder_by'] as String?,
        folderSuggestion: json['folder_suggestion'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// The title shown in the UI. The title is filled in by the AI (or from
  /// extraction) in the background; until then, or if the content really
  /// can't be read (e.g. a private post), show the URL.
  String get displayTitle => title?.isNotEmpty == true ? title! : url;

  /// 'youtube' | 'tiktok' | 'instagram' | 'web'. From the backend once
  /// processed; before that, guessed from the URL (same rules as
  /// backend/extraction.detect_platform) so a fresh row already has an icon.
  String get platformKey {
    final p = platform ?? platformFromUrl(url);
    return p == 'generic' ? 'web' : p;
  }

  /// "YouTube", "TikTok", "Instagram" or "Web".
  String get platformName => const {
        'youtube': 'YouTube',
        'tiktok': 'TikTok',
        'instagram': 'Instagram',
      }[platformKey] ??
      'Web';

  /// "Open in YouTube" / "Open in browser".
  String get openLabel => platformKey == 'web' ? 'Open in browser' : 'Open in $platformName';
}

String platformFromUrl(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.)'), '');
  if (host == 'youtube.com' || host == 'youtu.be' || host == 'music.youtube.com') return 'youtube';
  if (host == 'tiktok.com' || host.endsWith('.tiktok.com')) return 'tiktok';
  if (host == 'instagram.com' || host == 'instagr.am') return 'instagram';
  return 'web';
}

/// One result from POST /search: item + similarity score (cosine similarity).
/// The score is only meaningful for comparing results within the same
/// search, not an absolute relevance percentage (see backend/routers/search.py)
/// -- which is why the app doesn't show it.
class SearchResult {
  final Item item;
  final double score;

  SearchResult({required this.item, required this.score});

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        item: Item.fromJson(json),
        score: (json['score'] as num).toDouble(),
      );
}
