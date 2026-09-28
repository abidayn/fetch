import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../logic/library.dart';
import '../models/folder.dart';
import '../models/item.dart';
import '../util/open_link.dart';
import '../widgets/folder_actions.dart';
import '../widgets/folder_name_dialog.dart';
import '../widgets/item_actions.dart';
import '../widgets/item_row.dart';
import '../widgets/paste_sheet.dart';
import '../widgets/platform_badge.dart';
import '../widgets/save_result_sheet.dart';
import 'folders_screen.dart';
import 'needs_you_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// The library: the one root screen. Search sits on top because finding
/// things is the product; folder chips below it; then "Needs you", "From a
/// while ago" and the saves themselves. No bottom navigation: one root, one
/// retrieval action.
class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;
  final ValueNotifier<ThemeMode> themeMode;

  /// Log out / account deleted / session expired: back to the auth screen.
  final VoidCallback onSignedOut;

  const HomeScreen({super.key, required this.apiClient, required this.themeMode, required this.onSignedOut});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

/// The State is exposed (not prefixed with `_`) so main.dart can reach it
/// through a GlobalKey when a link arrives via the share sheet, without a
/// state management library for this one case.
class HomeScreenState extends State<HomeScreen> {
  // Explicit state, not a FutureBuilder: edits change the list in place, and
  // a failed refresh while old data is still there is just a snackbar.
  List<Item>? _items;
  List<Folder>? _folders;
  ApiException? _error;
  bool _loading = false;
  bool _slow = false; // the first load is taking a while (server waking up)
  String? _email;

  // null = All, [_unsorted] = no folder, otherwise a folder id. Filtered in
  // the app: all of the user's items are already loaded.
  String? _filter;
  static const _unsorted = '__unsorted__';

  // AI enrichment runs in the background for 5-10 seconds AFTER an item is
  // saved. While any item is unprocessed, the list reloads every 4 seconds --
  // capped at 10 times (~40 s) so it doesn't poll forever if the server has
  // problems. Each reload is a GET /items, which is also what triggers the
  // backend's throttled upgrade pass.
  static const _pollInterval = Duration(seconds: 4);
  static const _maxPolls = 10;
  Timer? _pollTimer;
  int _polls = 0;

  // Saves whose sheet was closed before Fetch finished: when they finish, a
  // snackbar says where they went (or that they need you).
  final _watching = <String>{};

  late final _callbacks = ItemCallbacks(onChanged: upsert, onDeleted: _remove);

  @override
  void initState() {
    super.initState();
    _load();
    widget.apiClient.myEmail().then((e) {
      if (mounted) setState(() => _email = e);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // --- loading -------------------------------------------------------------------

  Future<void> _load({bool fromPoll = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (_items == null) _error = null;
    });
    // "Connecting to Fetch…" becomes "waking up" if the first load drags on
    // (Railway's server sleeps when idle and takes a while to start).
    final slowTimer = _items == null ? Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _slow = true);
    }) : null;
    try {
      final raw = await widget.apiClient.listItems();
      if (!mounted) return;
      final items = raw.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
      setState(() {
        _items = items;
        _error = null;
      });
      _checkWatched();
      // Polls only reload the folder list when an item landed in a folder we
      // don't know yet (accepting a suggestion creates one).
      if (!fromPoll || items.any(_inUnknownFolder)) _loadFolders();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_items == null || e.isUnauthorized) {
        setState(() => _error = e);
      } else if (!fromPoll) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't refresh: ${e.message}")));
      }
    } finally {
      slowTimer?.cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _slow = false;
        });
        _schedulePollIfPending();
      }
    }
  }

  Future<void> _loadFolders() async {
    try {
      final raw = await widget.apiClient.listFolders();
      if (!mounted) return;
      setState(() => _folders = raw.map((e) => Folder.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException {
      // Keep the old list; the items still show.
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

  bool _inUnknownFolder(Item it) => it.folderId != null && !(_folders?.any((f) => f.id == it.folderId) ?? false);

  // --- used by main.dart and child screens ------------------------------------------

  /// Insert or replace one item (a new save, an edit, a folder change).
  void upsert(Item item) {
    if (!mounted) return;
    setState(() {
      final items = _items ?? [];
      final i = items.indexWhere((it) => it.id == item.id);
      _items = i < 0 ? [item, ...items] : [for (final it in items) it.id == item.id ? item : it];
    });
    if (_inUnknownFolder(item)) _loadFolders();
    _checkWatched();
    _schedulePollIfPending();
  }

  void _remove(Item removed) {
    setState(() => _items = _items?.where((it) => it.id != removed.id).toList());
  }

  /// Say where this save went once Fetch has finished with it (its sheet was
  /// closed before that).
  void watchFiling(String itemId) {
    _watching.add(itemId);
    _checkWatched();
    refresh();
  }

  void _checkWatched() {
    final items = _items;
    if (items == null || _watching.isEmpty) return;
    for (final id in [..._watching]) {
      final it = items.where((x) => x.id == id).firstOrNull;
      if (it == null) {
        _watching.remove(id);
        continue;
      }
      if (!it.processed) continue;
      // The close-time "Let Fetch pick" may still be on its way.
      if (it.folderBy == null && it.folderId == null) continue;
      _watching.remove(id);
      final String? message;
      if (it.folderId != null) {
        message = '"${it.title ?? 'Link'}" filed in ${it.folderName}';
      } else if (it.suggestionWaiting) {
        message = 'Fetch suggests a "${it.folderSuggestion}" folder. It\'s waiting in Needs you.';
      } else if (needReasons(it).isNotEmpty) {
        message = "A new save needs a folder. It's waiting in Needs you.";
      } else {
        message = null;
      }
      if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void openFolder(String folderId) => setState(() => _filter = folderId);

  // --- actions -------------------------------------------------------------------

  Future<void> _paste() async {
    final url = await showPasteSheet(context);
    if (url == null || !mounted) return;
    await _save(url);
  }

  Future<void> _save(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Saving…'), duration: Duration(seconds: 30)));
    try {
      final item = Item.fromJson(await widget.apiClient.createItem(url));
      messenger.hideCurrentSnackBar();
      upsert(item);
      setState(() => _filter = null);
      if (!mounted) return;
      Item latest = item;
      await showSaveResultSheet(context, widget.apiClient, item,
          onChanged: (it) {
            latest = it;
            upsert(it);
          },
          onToast: (m) => messenger.showSnackBar(SnackBar(content: Text(m))));
      if (!latest.processed || latest.waitingForAi) watchFiling(item.id);
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

  Folder? get _selectedFolder {
    final id = _filter;
    if (id == null || id == _unsorted) return null;
    return _folders?.where((f) => f.id == id).firstOrNull;
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => SearchScreen(
            apiClient: widget.apiClient,
            scope: _selectedFolder,
            callbacks: _callbacks,
            onOpenFolder: openFolder,
          ),
        ))
        .then((_) => refresh());
  }

  Future<void> _openFolders() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FoldersScreen(apiClient: widget.apiClient, items: _items ?? const [], onOpenFolder: openFolder),
    ));
    if (mounted) refresh();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(
        apiClient: widget.apiClient,
        items: _items ?? const [],
        folderCount: _folders?.length ?? 0,
        themeMode: widget.themeMode,
        onOpenFolder: openFolder,
        onSignedOut: widget.onSignedOut,
      ),
    ));
    if (mounted) refresh();
  }

  Future<void> _openNeedsYou() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NeedsYouScreen(apiClient: widget.apiClient, items: _items ?? const [], callbacks: _callbacks),
    ));
    if (mounted) refresh();
  }

  Future<void> _createFolder() async {
    final folder = await createFolderInteractively(context, widget.apiClient);
    if (folder == null || !mounted) return;
    setState(() => _folders = [...?_folders, folder]);
  }

  Future<void> _folderOptions(Folder folder) async {
    final saves = _items?.where((it) => it.folderId == folder.id).length ?? 0;
    if (await showFolderOptions(context, widget.apiClient, folder, saves: saves) && mounted) {
      if (!(await _folderStillExists(folder))) setState(() => _filter = null);
      refresh();
    }
  }

  Future<bool> _folderStillExists(Folder folder) async {
    await _loadFolders();
    return _folders?.any((f) => f.id == folder.id) ?? false;
  }

  // --- building ------------------------------------------------------------------

  Widget _top(ThemeData theme) {
    final folder = _selectedFolder;
    final label = folder != null
        ? 'Search in ${folder.name}'
        : _filter == _unsorted
            ? 'Search your saves'
            : 'Search or ask your saves';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.pets, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('Fetch', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: CircleAvatar(
              radius: 16,
              child: Text((_email ?? '?').substring(0, 1).toUpperCase()),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: _openSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// All · Unsorted (right after All, where it can't hide past the scroll
  /// edge) · the 4 most recently used folders · All folders.
  Widget _chips(List<Item> items) {
    final folders = _folders ?? const <Folder>[];
    final unsorted = items.where((it) => it.folderId == null).length;
    int count(String id) => items.where((it) => it.folderId == id).length;

    Widget chip(String label, String? value, {VoidCallback? onLongPress}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: ChoiceChip(
              label: Text(label),
              selected: _filter == value,
              onSelected: (sel) => setState(() => _filter = sel ? value : null),
            ),
          ),
        );

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          chip('All ${items.length}', null),
          if (unsorted > 0 || _filter == _unsorted) chip('Unsorted $unsorted', _unsorted),
          for (final f in chipFolders(folders, items, _filter))
            chip('${f.name} ${count(f.id)}', f.id, onLongPress: () => _folderOptions(f)),
          if (folders.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.folder_outlined, size: 18),
              label: Text('All folders ${folders.length}'),
              onPressed: _openFolders,
            )
          else
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Folder'), onPressed: _createFolder),
        ],
      ),
    );
  }

  Widget _needsBanner(ThemeData theme, List<Item> items) {
    final list = needsYou(items);
    if (list.isEmpty) return const SizedBox.shrink();
    final n = list.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.tertiaryContainer,
        child: ListTile(
          leading: const Icon(Icons.pets),
          title: Text('$n save${n == 1 ? '' : 's'} need${n == 1 ? 's' : ''} you'),
          subtitle: Text(needsSummary(list)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openNeedsYou,
        ),
      ),
    );
  }

  Widget _strip(ThemeData theme, List<Item> old) {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionHead(theme, 'From a while ago', trailing: Text('Picked for today', style: theme.textTheme.bodySmall)),
      SizedBox(
        height: 138,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final it in old)
              SizedBox(
                width: 200,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openLink(context, it.url),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        PlatformBadge(platform: it.platformKey, size: 32),
                        const SizedBox(height: 8),
                        Text(it.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                        const Spacer(),
                        Text('Saved ${timeAgo(it.createdAt, now).toLowerCase()}', style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  Widget _sectionHead(ThemeData theme, String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
        child: Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          ?trailing,
        ]),
      );

  Widget _rows(List<Item> list) => Column(children: [
        for (final it in list) ...[
          ItemRow(key: ValueKey(it.id), apiClient: widget.apiClient, item: it, callbacks: _callbacks),
          const Divider(height: 1, indent: 72),
        ],
      ]);

  Widget _message(ThemeData theme, {required String title, required String detail, Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(48),
            ),
            child: Text('Mascot', style: theme.textTheme.labelSmall),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(detail, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action],
        ]),
      );

  List<Widget> _body(ThemeData theme) {
    final items = _items;
    final error = _error;
    if (error != null && error.isUnauthorized) {
      return [
        _message(theme,
            title: 'Your session has expired',
            detail: 'Log in again to see your saves.',
            action: FilledButton(onPressed: widget.onSignedOut, child: const Text('Log in again'))),
      ];
    }
    if (items == null) {
      if (error != null) {
        return [
          _message(theme,
              title: "Can't reach Fetch",
              detail: 'Check your connection. Everything you saved is safe.',
              action: FilledButton.tonal(onPressed: _loading ? null : refresh, child: const Text('Try again'))),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(_slow ? 'The server is waking up. This can take a few seconds…' : 'Connecting to Fetch…',
              style: theme.textTheme.bodyMedium),
        ),
        for (var i = 0; i < 4; i++)
          ListTile(
            leading: Container(
                width: 44, height: 44, decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(11))),
            title: Container(height: 12, color: theme.colorScheme.surfaceContainerHighest),
            subtitle: Container(height: 10, margin: const EdgeInsets.only(top: 8, right: 60), color: theme.colorScheme.surfaceContainerHighest),
          ),
      ];
    }
    if (items.isEmpty) {
      return [
        _chips(items),
        _message(theme,
            title: 'Nothing saved yet',
            detail: 'Open TikTok, YouTube, Instagram or your browser, tap Share, then choose Fetch.',
            action: FilledButton.tonal(onPressed: _paste, child: const Text('Paste a link instead'))),
      ];
    }

    final filter = _filter;
    final folder = _selectedFolder;
    final list = filter == null
        ? items
        : filter == _unsorted
            ? items.where((it) => it.folderId == null).toList()
            : items.where((it) => it.folderId == filter).toList();
    final head = filter == null ? 'Recent' : filter == _unsorted ? 'Unsorted' : folder?.name ?? '';
    final n = '${list.length} save${list.length == 1 ? '' : 's'}';
    final sectionHead = _sectionHead(theme, head,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(n, style: theme.textTheme.bodySmall),
          // A real folder gets its menu (rename, delete) right where it's browsed.
          if (folder != null)
            IconButton(
              tooltip: 'Options for ${folder.name}',
              icon: const Icon(Icons.more_vert),
              onPressed: () => _folderOptions(folder),
            ),
        ]));

    final now = DateTime.now();
    final old = filter == null ? fromAWhileAgo(items, now) : const <Item>[];
    final out = <Widget>[_chips(items)];
    if (filter == null) out.add(_needsBanner(theme, items));
    if (list.isEmpty) {
      return [
        ...out,
        sectionHead,
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No saves in this folder yet. Pick it when you share something.',
              style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        ),
      ];
    }
    // Right after a save the newest rows come first, so the new one is on
    // screen; the resurfacing strip moves below them.
    if (old.isNotEmpty && hasFreshSave(items, now) && list.length > 3) {
      return [
        ...out,
        sectionHead,
        _rows(list.take(3).toList()),
        _strip(theme, old),
        _sectionHead(theme, 'Earlier'),
        _rows(list.skip(3).toList()),
      ];
    }
    return [
      ...out,
      if (old.isNotEmpty) _strip(theme, old),
      sectionHead,
      _rows(list),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems = _items?.isNotEmpty ?? false;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96), // room for the FAB
            children: [_top(theme), ..._body(theme)],
          ),
        ),
      ),
      floatingActionButton: hasItems
          ? FloatingActionButton(onPressed: _paste, tooltip: 'Paste a link', child: const Icon(Icons.add))
          : null,
    );
  }
}
