import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../logic/library.dart';
import '../models/folder.dart';
import '../models/item.dart';
import '../widgets/folder_actions.dart';
import '../widgets/folder_name_dialog.dart';
import '../widgets/folder_picker.dart' show kFolderSearchThreshold;

/// All folders: the folder browser and the place to manage them are one
/// screen. Tap a folder to open it on home; ⋮ to rename or delete it.
/// Sorted by name so a folder is easy to look up (home's chips already
/// cover the recent ones). Reached from the "All folders" chip and Settings.
class FoldersScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// For the Unsorted count (folders' own counts come from GET /folders).
  final List<Item> items;

  /// Opens a folder on home (null = Unsorted is handled as its own filter).
  final ValueChanged<String> onOpenFolder;

  const FoldersScreen({super.key, required this.apiClient, required this.items, required this.onOpenFolder});

  /// The filter value home uses for "Unsorted".
  static const unsortedId = '__unsorted__';

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<Folder>? _folders;
  String? _error;
  final _find = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.apiClient.listFolders();
      if (mounted) {
        setState(() {
          _folders = raw.map((e) => Folder.fromJson(e as Map<String, dynamic>)).toList();
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _open(String id) {
    // Back to home (wherever this screen was opened from), with the folder open.
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.onOpenFolder(id);
  }

  Future<void> _create() async {
    final folder = await createFolderInteractively(context, widget.apiClient);
    if (folder != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unsorted = widget.items.where((it) => it.folderId == null).length;
    final folders = _folders;
    final now = DateTime.now();

    Widget body;
    if (folders == null) {
      body = _error != null
          ? Center(child: TextButton(onPressed: _load, child: Text("Couldn't load folders: $_error. Retry")))
          : const Center(child: CircularProgressIndicator());
    } else {
      final searchable = folders.length > kFolderSearchThreshold;
      final shown = filterFolders(byName(folders), searchable ? _find.text : '');
      body = ListView(children: [
        if (unsorted > 0)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Unsorted'),
              subtitle: Text('$unsorted save${unsorted == 1 ? '' : 's'} without a folder'),
              onTap: () => _open(FoldersScreen.unsortedId),
            ),
          ),
        if (folders.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No folders yet. Create one here, or let Fetch suggest one when you save.',
                textAlign: TextAlign.center),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              if (searchable)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _find,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Find a folder',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              if (searchable && shown.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('No folder with that name.')),
              for (final f in shown)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  subtitle: Text([
                    '${f.itemCount} save${f.itemCount == 1 ? '' : 's'}',
                    if (f.lastSavedAt != null) 'last save ${timeAgo(f.lastSavedAt!, now).toLowerCase()}',
                  ].join(' · ')),
                  onTap: () => _open(f.id),
                  trailing: IconButton(
                    tooltip: 'Options for ${f.name}',
                    icon: const Icon(Icons.more_vert),
                    onPressed: () async {
                      if (await showFolderOptions(context, widget.apiClient, f, saves: f.itemCount)) _load();
                    },
                  ),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.tonalIcon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New folder')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Text('Deleting a folder never deletes saves. They move to Unsorted.',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ),
      ]);
    }
    return Scaffold(appBar: AppBar(title: const Text('Folders')), body: body);
  }
}
