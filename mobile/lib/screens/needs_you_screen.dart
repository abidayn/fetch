import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../logic/library.dart';
import '../models/item.dart';
import '../widgets/item_actions.dart';
import '../widgets/item_row.dart';

/// Everything Fetch saved but couldn't finish alone, with a one-tap fix under
/// each save (logic/library.dart decides what belongs here):
/// - a folder Fetch proposed          -> Create "X" / Pick another
/// - a link it couldn't read          -> Add a title (so search can find it)
/// - a save nobody put in a folder    -> Pick a folder
/// "Leave it in Unsorted" in the save sheet counts as a decision, so those
/// saves don't come back here.
class NeedsYouScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<Item> items;
  final ItemCallbacks callbacks;
  const NeedsYouScreen({super.key, required this.apiClient, required this.items, required this.callbacks});

  @override
  State<NeedsYouScreen> createState() => _NeedsYouScreenState();
}

class _NeedsYouScreenState extends State<NeedsYouScreen> {
  // Own copy: a fixed save drops off this list right away, and the list
  // behind (home) is updated through the callbacks.
  late List<Item> _items = [...widget.items];
  final _busy = <String>{};

  late final _cb = ItemCallbacks(
    onChanged: (it) {
      setState(() => _items = [for (final x in _items) x.id == it.id ? it : x]);
      widget.callbacks.onChanged(it);
    },
    onDeleted: (it) {
      setState(() => _items = _items.where((x) => x.id != it.id).toList());
      widget.callbacks.onDeleted(it);
    },
  );

  Future<void> _accept(Item it) async {
    setState(() => _busy.add(it.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = Item.fromJson(await widget.apiClient.setItemFolder(it.id, acceptSuggestion: true));
      _cb.onChanged(updated);
      messenger.showSnackBar(SnackBar(content: Text('Created "${updated.folderName}" and filed it there')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't create the folder: ${e.message}")));
    } finally {
      if (mounted) setState(() => _busy.remove(it.id));
    }
  }

  Widget _fixes(Item it) {
    final reasons = needReasons(it);
    final busy = _busy.contains(it.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (reasons.contains(NeedReason.suggestion))
          FilledButton.icon(
            onPressed: busy ? null : () => _accept(it),
            icon: const Icon(Icons.add, size: 18),
            label: Text('Create "${it.folderSuggestion}"'),
          ),
        if (reasons.contains(NeedReason.unreadable))
          OutlinedButton.icon(
            onPressed: busy ? null : () => editItem(context, widget.apiClient, it, _cb),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Add a title'),
          ),
        if (reasons.contains(NeedReason.suggestion) || reasons.contains(NeedReason.noFolder))
          OutlinedButton.icon(
            onPressed: busy ? null : () => moveItem(context, widget.apiClient, it, _cb),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: Text(reasons.contains(NeedReason.suggestion) ? 'Pick another' : 'Pick a folder'),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = needsYou(_items)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Needs you')),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('All sorted', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Every save has a folder and something search can find.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.tonal(onPressed: () => Navigator.pop(context), child: const Text('Back to your saves')),
                ]),
              ),
            )
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text("Fetch saved these but couldn't finish them alone. One tap each.",
                    style: theme.textTheme.bodyMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(children: [
                  Expanded(
                      child: Text('${list.length} save${list.length == 1 ? '' : 's'}',
                          style: theme.textTheme.titleMedium)),
                  Flexible(child: Text(needsSummary(list), style: theme.textTheme.bodySmall, textAlign: TextAlign.end)),
                ]),
              ),
              for (final it in list) ...[
                ItemRow(
                  key: ValueKey(it.id),
                  apiClient: widget.apiClient,
                  item: it,
                  callbacks: _cb,
                  below: _fixes(it),
                ),
                const Divider(height: 1, indent: 72),
              ],
            ]),
    );
  }
}
