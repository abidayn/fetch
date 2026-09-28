import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/folder.dart';
import '../models/item.dart';
import 'folder_name_dialog.dart';
import 'folder_picker.dart';

/// "Move to folder" (or "Pick a folder" for an Unsorted save): the folder
/// picker for an item that's already saved. Returns the updated item, or
/// null if closed without choosing. Works while the item is still being
/// processed too: a folder choice doesn't clash with the AI's text.
Future<Item?> showMoveSheet(BuildContext context, ApiClient apiClient, Item item) {
  return showModalBottomSheet<Item>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MoveSheet(apiClient: apiClient, item: item),
  );
}

class _MoveSheet extends StatefulWidget {
  final ApiClient apiClient;
  final Item item;
  const _MoveSheet({required this.apiClient, required this.item});

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  List<Folder>? _folders;
  String? _foldersError;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.apiClient.listFolders();
      if (mounted) setState(() => _folders = raw.map((e) => Folder.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _foldersError = e.message);
    }
  }

  Future<void> _move(Folder folder) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final json = await widget.apiClient.setItemFolder(widget.item.id, folderId: folder.id);
      if (mounted) Navigator.pop(context, Item.fromJson(json));
    } on ApiException catch (e) {
      // Inline, not a snackbar: a snackbar would appear behind this sheet.
      if (mounted) setState(() => _error = "Couldn't move it: ${e.message}");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _create(String initial) async {
    final name = await showFolderNameDialog(context, initial: initial);
    if (name == null || !mounted) return;
    try {
      await _move(Folder.fromJson(await widget.apiClient.createFolder(name)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = "Couldn't create the folder: ${e.message}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.item.folderId == null ? 'Pick a folder' : 'Move to folder', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        if (_saving) const LinearProgressIndicator(),
        FolderPicker(
          folders: _folders,
          foldersError: _foldersError,
          onRetryFolders: _load,
          selectedId: widget.item.folderId,
          onPickFolder: _move,
          onCreate: _create,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
      ]),
    );
  }
}
