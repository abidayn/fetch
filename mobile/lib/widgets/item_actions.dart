import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../screens/item_detail_screen.dart';
import '../util/open_link.dart';
import 'edit_item_sheet.dart';
import 'move_sheet.dart';
import 'platform_badge.dart';

/// What a screen showing items does when one changes or disappears.
class ItemCallbacks {
  final ValueChanged<Item> onChanged;
  final ValueChanged<Item> onDeleted;
  const ItemCallbacks({required this.onChanged, required this.onDeleted});
}

/// The item menu (row ⋮ or long-press): Open, Details, Move / Pick a folder,
/// Edit (not while Fetch is still reading it), Share link, Delete. Tapping
/// the row itself opens the original post -- that's why people come back --
/// so everything else lives here.
Future<void> showItemMenu(BuildContext context, ApiClient apiClient, Item item, ItemCallbacks cb) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final danger = theme.colorScheme.error;
      Widget row(String value, IconData icon, String title, {String? sub, bool enabled = true, Color? color}) => ListTile(
            enabled: enabled,
            leading: Icon(icon, color: color),
            title: Text(title, style: color == null ? null : TextStyle(color: color)),
            subtitle: sub == null ? null : Text(sub),
            onTap: () => Navigator.pop(ctx, value),
          );
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: PlatformBadge(platform: item.platformKey, size: 40),
            title: Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          row('open', Icons.open_in_new, item.openLabel),
          row('details', Icons.info_outline, 'Details', sub: 'Full summary, who filed it, the link'),
          row('move', Icons.drive_file_move_outline, item.folderId == null ? 'Pick a folder' : 'Move to folder',
              sub: 'Now in ${item.folderName ?? 'Unsorted'}'),
          row('edit', Icons.edit_outlined, item.hasContent || !item.processed ? 'Edit title and summary' : 'Add a title',
              sub: item.processed ? null : 'Available once Fetch has read it', enabled: item.processed),
          row('share', Icons.share_outlined, 'Share link'),
          row('delete', Icons.delete_outline, 'Delete', color: danger),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      await openLink(context, item.url);
    case 'details':
      await openItemDetail(context, apiClient, item, cb);
    case 'move':
      await moveItem(context, apiClient, item, cb);
    case 'edit':
      await editItem(context, apiClient, item, cb);
    case 'share':
      await shareItem(item);
    case 'delete':
      await deleteItem(context, apiClient, item, cb);
  }
}

Future<void> openItemDetail(BuildContext context, ApiClient apiClient, Item item, ItemCallbacks cb) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ItemDetailScreen(apiClient: apiClient, item: item, callbacks: cb),
  ));
}

Future<Item?> moveItem(BuildContext context, ApiClient apiClient, Item item, ItemCallbacks cb) async {
  final updated = await showMoveSheet(context, apiClient, item);
  if (updated == null || !context.mounted) return null;
  cb.onChanged(updated);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved to ${updated.folderName ?? 'Unsorted'}')));
  return updated;
}

Future<Item?> editItem(BuildContext context, ApiClient apiClient, Item item, ItemCallbacks cb) async {
  final updated = await showEditItemSheet(context, apiClient, item);
  if (updated == null || !context.mounted) return null;
  cb.onChanged(updated);
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved. Fetch won't overwrite your edit.")));
  return updated;
}

/// Android's share menu (it already includes "Copy").
Future<void> shareItem(Item item) async {
  try {
    await SharePlus.instance.share(ShareParams(text: item.url, subject: item.title));
  } catch (_) {
    // No share target available: nothing sensible to do.
  }
}

/// Returns true if the item was deleted.
Future<bool> deleteItem(BuildContext context, ApiClient apiClient, Item item, ItemCallbacks cb) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this save?'),
      content: const Text("It's removed from Fetch. The original post isn't affected."),
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
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await apiClient.deleteItem(item.id);
    cb.onDeleted(item);
    messenger.showSnackBar(const SnackBar(content: Text('Deleted')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't delete: ${e.message}")));
    return false;
  }
}
