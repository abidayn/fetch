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
