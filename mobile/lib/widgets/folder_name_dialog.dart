import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/folder.dart';

/// Same limit as the backend (folders.MAX_NAME_LEN). Checked there too; here
/// it only stops the user typing a name the backend would reject.
const kMaxFolderNameLength = 40;

/// Asks for a folder name. Returns the trimmed name, or null if cancelled.
/// Used for both "New folder" and "Rename".
Future<String?> showFolderNameDialog(
  BuildContext context, {
  String title = 'New folder',
  String action = 'Create',
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderNameDialog(title: title, action: action, initial: initial),
  );
}

/// "New folder" end to end: ask for a name, create it, report a failure
/// (e.g. a duplicate name) in a snackbar. Returns the new folder, or null.
Future<Folder?> createFolderInteractively(BuildContext context, ApiClient apiClient) async {
  final name = await showFolderNameDialog(context);
  if (name == null || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  try {
    return Folder.fromJson(await apiClient.createFolder(name));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't create the folder: ${e.message}")));
    return null;
  }
}

class _FolderNameDialog extends StatefulWidget {
  final String title;
  final String action;
  final String initial;
  const _FolderNameDialog({required this.title, required this.action, required this.initial});

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _name => _ctrl.text.trim();

  void _submit() {
    if (_name.isNotEmpty) Navigator.pop(context, _name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: kMaxFolderNameLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Weeknight dinners'),
        onChanged: (_) => setState(() {}), // re-evaluate the button's enabled state
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _name.isEmpty ? null : _submit, child: Text(widget.action)),
      ],
    );
  }
}
