import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/folder.dart';
import 'folder_name_dialog.dart';

/// A folder's options sheet (Rename / Delete), shared by home (chip
/// long-press, the section's ⋮) and the Folders screen. Returns true when
/// the folder changed, so the caller reloads.
Future<bool> showFolderOptions(BuildContext context, ApiClient apiClient, Folder folder, {required int saves}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder.name, style: theme.textTheme.titleMedium),
            subtitle: Text(saves == 1 ? '1 save' : '$saves saves'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text('Delete folder', style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text('Its saves move to Unsorted'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      );
    },
  );
  if (!context.mounted) return false;
  if (action == 'rename') return renameFolder(context, apiClient, folder);
  if (action == 'delete') return deleteFolder(context, apiClient, folder, saves: saves);
  return false;
}

Future<bool> renameFolder(BuildContext context, ApiClient apiClient, Folder folder) async {
  final name = await showFolderNameDialog(context, title: 'Rename folder', action: 'Save', initial: folder.name);
  if (name == null || name == folder.name || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await apiClient.renameFolder(folder.id, name);
    messenger.showSnackBar(const SnackBar(content: Text('Renamed')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't rename: ${e.message}")));
    return false;
  }
}

Future<bool> deleteFolder(BuildContext context, ApiClient apiClient, Folder folder, {required int saves}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${folder.name}"?'),
      content: Text(saves == 0
          ? 'The folder is empty.'
          : 'Its ${saves == 1 ? 'save moves' : '$saves saves move'} to Unsorted. Nothing is deleted.'),
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
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await apiClient.deleteFolder(folder.id);
    messenger.showSnackBar(SnackBar(content: Text('Deleted "${folder.name}"')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't delete the folder: ${e.message}")));
    return false;
  }
}
