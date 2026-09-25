import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';

/// Form for editing title / summary / category. Returns the backend's new
/// version of the item if saved, null if cancelled.
///
/// Meant for correcting AI output that missed (wrong category, a generic
/// title like "YouTube" when yt-dlp was blocked) -- not retyping from scratch.
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
  late String? _category = widget.item.category;

  List<String>? _categories;
  String? _categoriesError;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _categoriesError = null);
    try {
      final cats = await widget.apiClient.listCategories();
      if (mounted) setState(() => _categories = cats);
    } on ApiException catch (e) {
      if (mounted) setState(() => _categoriesError = e.message);
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = "Title can't be empty.");
      return;
    }
    final summary = _summaryCtrl.text.trim();
    final item = widget.item;

    // Send only what changed: the backend re-embeds only when title / summary
    // change (one Gemini call); changing just the category doesn't.
    final newTitle = title != (item.title ?? '') ? title : null;
    final newSummary = summary != (item.summary ?? '') ? summary : null;
    final newCategory = _category != item.category ? _category : null;
    if (newTitle == null && newSummary == null && newCategory == null) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final json = await widget.apiClient
          .updateItem(item.id, title: newTitle, summary: newSummary, category: newCategory);
      if (!mounted) return;
      Navigator.pop(context, Item.fromJson(json));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _categoryField() {
    final cats = _categories;
    if (cats == null) {
      if (_categoriesError != null) {
        return Row(children: [
          Expanded(child: Text("Couldn't load categories: $_categoriesError")),
          TextButton(onPressed: _loadCategories, child: const Text('Try again')),
        ]);
      }
      return const LinearProgressIndicator();
    }
    return DropdownButtonFormField<String>(
      initialValue: cats.contains(_category) ? _category : null,
      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
      items: [for (final c in cats) DropdownMenuItem(value: c, child: Text(c))],
      onChanged: _saving ? null : (v) => setState(() => _category = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text('Edit item', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                widget.item.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                enabled: !_saving,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _summaryCtrl,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Summary', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              _categoryField(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
