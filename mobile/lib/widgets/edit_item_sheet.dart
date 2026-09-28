import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';

/// "Edit" (or "Add a title" for a link Fetch couldn't read): title and
/// summary. Returns the backend's new version of the item if saved, null if
/// cancelled.
///
/// Meant for correcting AI output that missed (a generic title like
/// "YouTube" when yt-dlp was blocked) or naming an unreadable link so search
/// can find it. Saving marks the item as written by the user
/// (classified_by 'user'), so Fetch never rewrites it.
Future<Item?> showEditItemSheet(BuildContext context, ApiClient apiClient, Item item) {
  return showModalBottomSheet<Item>(
    context: context,
    isScrollControlled: true, // so the sheet can move up above the keyboard
    showDragHandle: true,
    builder: (_) => _EditItemSheet(apiClient: apiClient, item: item),
  );
}

class _EditItemSheet extends StatefulWidget {
  final ApiClient apiClient;
  final Item item;
  const _EditItemSheet({required this.apiClient, required this.item});

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late final _titleCtrl = TextEditingController(text: widget.item.title ?? '');
  late final _summaryCtrl = TextEditingController(text: widget.item.summary ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = "Title can't be empty.");
      return;
    }
    final summary = _summaryCtrl.text.trim();
    final item = widget.item;

    // Send only what changed: the backend re-embeds when title / summary
    // change (one Gemini call).
    final newTitle = title != (item.title ?? '') ? title : null;
    final newSummary = summary != (item.summary ?? '') ? summary : null;
    if (newTitle == null && newSummary == null) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final json = await widget.apiClient.updateItem(item.id, title: newTitle, summary: newSummary);
      if (!mounted) return;
      Navigator.pop(context, Item.fromJson(json));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addingTitle = !widget.item.hasContent && widget.item.title == null;
    return Padding(
      // viewInsets = keyboard height; without this the Save button is hidden by the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(addingTitle ? 'Add a title' : 'Edit', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                enabled: !_saving,
                autofocus: addingTitle,
                maxLength: 300,
                decoration: const InputDecoration(
                    labelText: 'Title', hintText: 'What is this?', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _summaryCtrl,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Summary',
                  hintText: 'A line or two so search can find it',
                  border: OutlineInputBorder(),
                ),
              ),
              Text(
                "Your edits are kept. Fetch won't rewrite them.",
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
