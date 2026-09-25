import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
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

  // null = "All". Browsing by category is filtered in the app: all of the
  // user's items are already loaded for this list, so no extra request.
  String? _category;

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
  }

  void _remove(Item removed) {
    setState(() {
      _items = _items!.where((it) => it.id != removed.id).toList();
    });
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SearchScreen(apiClient: widget.apiClient)))
        // Items can be edited/deleted from the search screen -- resync on return.
        .then((_) => refresh());
  }

  /// Chips for the categories the user actually has, largest first. Empty
  /// categories aren't shown -- a chip that always leads to an empty screen
  /// only confuses.
  Widget _categoryChips(List<Item> items) {
    final counts = <String, int>{};
    for (final it in items) {
      final c = it.category;
      if (c != null) counts[c] = (counts[c] ?? 0) + 1;
    }
    final cats = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('All (${items.length})'),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
          ),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$c (${counts[c]})'),
                selected: _category == c,
                onSelected: (sel) => setState(() => _category = sel ? c : null),
              ),
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

    // The selected category can disappear (its last item was deleted/edited).
    final category = items.any((it) => it.category == _category) ? _category : null;
    final visible = category == null ? items : items.where((it) => it.category == category).toList();

    return Column(children: [
      _categoryChips(items),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
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
