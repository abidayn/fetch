/// Mirror of the backend's `FolderPublic` schema (backend/schemas.py): one of
/// the user's own folders.
class Folder {
  final String id;
  final String name;

  /// From GET /folders. Screens that have every item loaded (home) count
  /// from those instead, so the numbers always match the list on screen.
  final int itemCount;

  /// Newest save in the folder (null = empty) and when the folder was made:
  /// together they give "most recently used" (see [lastUsed]).
  final DateTime? lastSavedAt;
  final DateTime? createdAt;

  Folder({required this.id, required this.name, required this.itemCount, this.lastSavedAt, this.createdAt});

  /// "Recently used" = the newest save in it, or when it was made.
  DateTime get lastUsed =>
      lastSavedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        name: json['name'] as String,
        itemCount: json['item_count'] as int? ?? 0,
        lastSavedAt: json['last_saved_at'] == null ? null : DateTime.parse(json['last_saved_at'] as String),
        createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
      );
}

/// Folders whose name contains [query], ignoring case; names that START with
/// it come first ("gym" -> "Gym" before "Home gym"), otherwise the input order
/// is kept. An empty query returns everything.
///
/// Done in the app, not the backend: every folder name (at most 50) is
/// already loaded via GET /folders, so matching is instant, works per
/// keystroke, and costs no request or AI quota -- unlike item search.
List<Folder> filterFolders(List<Folder> folders, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return folders;
  final starts = <Folder>[];
  final contains = <Folder>[];
  for (final f in folders) {
    final name = f.name.toLowerCase();
    if (name.startsWith(q)) {
      starts.add(f);
    } else if (name.contains(q)) {
      contains.add(f);
    }
  }
  return [...starts, ...contains];
}

/// Most recently used first: the folders you actually file into stay one
/// tap away (home chips, the folder picker) even with dozens of folders.
List<Folder> byRecent(List<Folder> folders) =>
    [...folders]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));

/// Alphabetical, for the All folders screen, where you look a name up.
List<Folder> byName(List<Folder> folders) =>
    [...folders]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
