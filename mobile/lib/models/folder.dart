/// Mirror of the backend's `FolderPublic` schema (backend/schemas.py): one of
/// the user's own folders. Folders are the user's grouping of items, next to
/// the AI's fixed `category` (which stays a search filter).
class Folder {
  final String id;
  final String name;

  /// From GET /folders. The home screen counts from its loaded items instead
  /// (always in sync with the list it filters); this is for places that don't
  /// have every item loaded, like the save sheet.
  final int itemCount;

  Folder({required this.id, required this.name, required this.itemCount});

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        name: json['name'] as String,
        itemCount: json['item_count'] as int? ?? 0,
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
