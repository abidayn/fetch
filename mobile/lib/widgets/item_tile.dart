import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../util/open_link.dart';
import 'edit_item_sheet.dart';

/// One item row, used on home and in search results.
///
/// Tap = open the link in its source app (the main action). Edit / delete
/// live in the ⋮ menu, deliberately not on tap/long-press so they aren't hit
/// while scrolling. [onChanged] is called with the new item after an edit;
/// [onDeleted] after the backend has actually deleted it -- the caller
/// updates the list.
class ItemTile extends StatelessWidget {
  final ApiClient apiClient;
  final Item item;
  final ValueChanged<Item> onChanged;
  final ValueChanged<Item> onDeleted;
  final Widget? leading;
  final Widget? trailingInfo;

  const ItemTile({
    super.key,
    required this.apiClient,
    required this.item,
    required this.onChanged,
    required this.onDeleted,
    this.leading,
    this.trailingInfo,
  });

  Widget _subtitle() {
    if (!item.processed) {
      return const Text('Processing…', style: TextStyle(fontStyle: FontStyle.italic));
    }
    final meta = [item.category, item.platform].whereType<String>().join(' · ');
    if (item.summary == null) {
      // Processed, but no readable content (e.g. a private post) -- show it
      // as is, not "processing" forever.
      return Text(meta.isEmpty ? item.url : meta, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text(
      [meta, item.summary!].where((s) => s.isNotEmpty).join('\n'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _edit(BuildContext context) async {
    final updated = await showEditItemSheet(context, apiClient, item);
    if (updated == null) return;
    onChanged(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changes saved.')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text(item.displayTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await apiClient.deleteItem(item.id);
      onDeleted(item);
      messenger.showSnackBar(const SnackBar(content: Text('Item deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't delete: ${e.message}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      minLeadingWidth: leading == null ? null : 24,
      title: Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: _subtitle(),
      isThreeLine: item.processed && item.summary != null,
      onTap: () => openLink(context, item.url),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailingInfo,
          PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (action) => switch (action) {
              'open' => openLink(context, item.url),
              'edit' => _edit(context),
              'delete' => _delete(context),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Open link'))),
              PopupMenuItem(
                value: 'edit',
                // AI output that's still processing would overwrite the edit
                // (the backend also rejects it with 409) -- block it in the UI.
                enabled: item.processed,
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  subtitle: item.processed ? null : const Text('Wait for the AI to finish'),
                  enabled: item.processed,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
