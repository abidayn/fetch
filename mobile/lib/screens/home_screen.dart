import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/folder.dart';
import '../models/item.dart';
import '../widgets/folder_name_dialog.dart';
import '../widgets/item_tile.dart';
import '../widgets/save_result_sheet.dart';
import 'login_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;
  final GlobalKey<HomeScreenState>? homeKey;
  const HomeScreen({super.key, required this.apiClient, this.homeKey});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

/// The State is exposed (not prefixed with `_`) so main.dart can call
/// `refresh()` through a GlobalKey when a new link arrives via the share
/// sheet, without needing a state management library for this one case.
class HomeScreenState extends State<HomeScreen> {
  // Explicit state, not a FutureBuilder: edit & delete change the list in
  // place (without reloading everything), and a failed refresh while old data
  // is still there is just a snackbar -- not an error replacing the whole screen.
  List<Item>? _items;
  ApiException? _error;
  bool _loading = false;

  // Browsing by folder. null = "All", [_unfiled] = items in no folder,
  // otherwise a folder id. Filtered in the app: all of the user's items are
  // already loaded for this list, so no extra request.
  String? _folderFilter;
  static const _unfiled = '__unfiled__';

  // The user's folders, loaded next to the items: the chips need their names,
  // and empty folders (just created) should show too. Counts come from the
  // loaded items instead, so they always match the list being filtered.
  List<Folder>? _folders;

  // AI enrichment runs in the background for 5-10 seconds AFTER an item is
  // saved, so a new item first shows as "processing". While any item is
  // unprocessed, the list reloads every 4 seconds -- capped at 10 times
  // (~40 seconds) so it doesn't poll forever if the server has problems.
  static const _pollInterval = Duration(seconds: 4);
  static const _maxPolls = 10;
  Timer? _pollTimer;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool fromPoll = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (_items == null) _error = null;
    });
    try {
      final raw = await widget.apiClient.listItems();
      if (!mounted) return;
      final items = raw.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
      setState(() {
        _items = items;
        _error = null;
      });
      // Polls only reload the folder list when an item landed in a folder we
      // don't know yet (the AI can create one while filing).
      if (!fromPoll || items.any(_inUnknownFolder)) _loadFolders();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_items == null || e.isUnauthorized) {
        setState(() => _error = e);
      } else if (!fromPoll) {
        // The old data is still useful -- just say so, don't blank the screen.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't refresh: ${e.message}")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        // In finally: a failed poll (brief network drop) is still rescheduled.
        _schedulePollIfPending();
      }
    }
  }

  void _schedulePollIfPending() {
    _pollTimer?.cancel();
    final pending = _items?.any((it) => !it.processed) ?? false;
    if (!pending || _polls >= _maxPolls || !mounted) return;
    _pollTimer = Timer(_pollInterval, () {
      if (!mounted) return;
      _polls++;
      _load(fromPoll: true);
    });
  }

  Future<void> refresh() {
    _polls = 0;
    return _load();
  }

  bool _inUnknownFolder(Item it) =>
      it.folderId != null && !(_folders?.any((f) => f.id == it.folderId) ?? false);

  /// Failures are quiet: the items still show, and chips fall back to what
  /// was loaded before (or just All/Unfiled).
  Future<void> _loadFolders() async {
    try {
      final raw = await widget.apiClient.listFolders();
      if (!mounted) return;
      setState(() => _folders = raw.map((e) => Folder.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException {
      // Keep the old list.
    }
  }

  Future<void> _createFolder() async {
    final folder = await createFolderInteractively(context, widget.apiClient);
    if (folder == null || !mounted) return;
    setState(() {
      _folders = [...?_folders, folder];
      _folderFilter = folder.id;
    });
  }

  Future<void> _renameFolder(Folder folder) async {
    final name = await showFolderNameDialog(context,
        title: 'Rename folder', action: 'Rename', initial: folder.name);
    if (name == null || name == folder.name || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.apiClient.renameFolder(folder.id, name);
      await _loadFolders();
      await refresh(); // the items carry the folder name too
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't rename: ${e.message}")));
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final count = _items?.where((it) => it.folderId == folder.id).length ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: Text(count == 0
            ? 'The folder is empty.'
            : 'Its ${count == 1 ? 'item stays' : '$count items stay'} saved and ${count == 1 ? 'moves' : 'move'} to Unfiled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.apiClient.deleteFolder(folder.id);
      setState(() {
        _folders = _folders?.where((f) => f.id != folder.id).toList();
        if (_folderFilter == folder.id) _folderFilter = null;
      });
      await refresh();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't delete the folder: ${e.message}")));
    }
  }

  Future<void> _folderActions(Folder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(folder.name, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete folder'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _renameFolder(folder);
    if (action == 'delete') await _deleteFolder(folder);
  }

  Folder? get _selectedFolder {
    final id = _folderFilter;
    if (id == null || id == _unfiled) return null;
    for (final f in _folders ?? const <Folder>[]) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> _logout() async {
    await widget.apiClient.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => LoginScreen(apiClient: widget.apiClient, homeKey: widget.homeKey)),
      (route) => false,
    );
  }

  /// Manual "paste a link" form -- a fallback when the source app has no
  /// share-to-Fetch button, and handy for testing.
  Future<void> _addManually() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save a link'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://...'),
          keyboardType: TextInputType.url,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _save(url);
  }

  Future<void> _save(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Saving…'), duration: Duration(seconds: 30)));
    try {
      final item = Item.fromJson(await widget.apiClient.createItem(url));
      messenger.hideCurrentSnackBar();
      refresh();
      if (!mounted) return;
      await showSaveResultSheet(context, widget.apiClient, item);
      refresh();
    } on ApiException catch (e) {
      messenger.hideCurrentSnackBar();
      // The POST isn't retried automatically (it could save twice), so the user decides.
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't save: ${e.message}"),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Try again', onPressed: () => _save(url)),
      ));
    }
  }

  void _replace(Item updated) {
    setState(() {
      _items = [for (final it in _items!) it.id == updated.id ? updated : it];
    });
    // Moved into a folder the AI just created: fetch its name for the chips.
    if (_inUnknownFolder(updated)) _loadFolders();
  }

  void _remove(Item removed) {
    setState(() {
      _items = _items!.where((it) => it.id != removed.id).toList();
    });
  }

  void _openSearch() {
    Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => SearchScreen(apiClient: widget.apiClient)))
        .then((folderId) {
      // Search returns a folder id when the user tapped a matching folder:
      // open it here, since home is where browsing by folder lives.
      if (folderId != null && mounted) setState(() => _folderFilter = folderId);
      // Items can be edited/deleted from the search screen -- resync on return.
      refresh();
    });
  }

  /// All · Unfiled · the user's folders (largest first) · + New folder.
  /// Unlike the old category chips, empty folders ARE shown: the user made
  /// them on purpose. Long-press a folder chip to rename or delete it.
  Widget _folderChips(List<Item> items) {
    final counts = <String, int>{};
    var unfiled = 0;
    for (final it in items) {
      final id = it.folderId;
      if (id == null) {
        unfiled++;
      } else {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final folders = [...?_folders]..sort((a, b) {
        final byCount = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
        return byCount != 0 ? byCount : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    Widget chip(String label, String? value, {VoidCallback? onLongPress}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: ChoiceChip(
              label: Text(label),
              selected: _folderFilter == value,
              onSelected: (sel) => setState(() => _folderFilter = sel ? value : null),
            ),
          ),
        );

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          chip('All (${items.length})', null),
          // Without folders, "Unfiled" would just repeat "All".
          if (folders.isNotEmpty && (unfiled > 0 || _folderFilter == _unfiled)) chip('Unfiled ($unfiled)', _unfiled),
          for (final f in folders) chip('${f.name} (${counts[f.id] ?? 0})', f.id, onLongPress: () => _folderActions(f)),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('New folder'),
            onPressed: _createFolder,
          ),
        ],
      ),
    );
  }

  /// A centred message that can still be pulled to refresh.
  Widget _message({required IconData icon, required String title, String? detail, Widget? action}) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(detail, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: 16), Center(child: action)],
      ],
    );
  }

  Widget _body() {
    final items = _items;
    final error = _error;

    if (error != null && error.isUnauthorized) {
      return _message(
        icon: Icons.lock_outline,
        title: 'Your session has expired',
        detail: 'Log in again to see your saved items.',
        action: FilledButton(onPressed: _logout, child: const Text('Log in again')),
      );
    }
    if (items == null) {
      if (error != null) {
        return _message(
          icon: Icons.cloud_off,
          title: "Couldn't load your items",
          detail: error.message,
          action: FilledButton.icon(
            onPressed: _loading ? null : refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return _message(
        icon: Icons.bookmark_add_outlined,
        title: 'Nothing saved yet',
        detail: 'In YouTube, TikTok, or your browser, tap Share and choose Fetch. '
            'Or tap + to paste a link.',
      );
    }

    final filter = _folderFilter;
    final List<Item> visible;
    if (filter == null) {
      visible = items;
    } else if (filter == _unfiled) {
      visible = items.where((it) => it.folderId == null).toList();
    } else {
      visible = items.where((it) => it.folderId == filter).toList();
    }

    return Column(children: [
      _folderChips(items),
      const Divider(height: 1),
      Expanded(
        child: visible.isEmpty
            ? _message(
                icon: Icons.folder_open,
                title: filter == _unfiled ? 'Everything is in a folder' : 'Nothing in this folder yet',
                detail: filter == _unfiled
                    ? null
                    : 'Choose it when you save a link, or use ⋮ → Move to folder on any item.',
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88), // room for the FAB
                itemCount: visible.length,
                itemBuilder: (context, i) => ItemTile(
                  key: ValueKey(visible[i].id),
                  apiClient: widget.apiClient,
                  item: visible[i],
                  onChanged: _replace,
                  onDeleted: _remove,
                ),
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fetch'),
        bottom: _loading && _items != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
        actions: [
          // The discoverable way to rename/delete the selected folder
          // (long-pressing its chip does the same).
          if (_selectedFolder case final folder?)
            IconButton(
              onPressed: () => _folderActions(folder),
              tooltip: 'Folder options',
              icon: const Icon(Icons.folder_open),
            ),
          IconButton(onPressed: _openSearch, tooltip: 'Search', icon: const Icon(Icons.search)),
          IconButton(onPressed: _logout, tooltip: 'Log out', icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(onRefresh: refresh, child: _body()),
      floatingActionButton: FloatingActionButton(
        onPressed: _addManually,
        tooltip: 'Save a link',
        child: const Icon(Icons.add),
      ),
    );
  }
}
