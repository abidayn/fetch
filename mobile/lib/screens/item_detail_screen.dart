import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../logic/library.dart';
import '../models/item.dart';
import '../util/open_link.dart';
import '../widgets/item_actions.dart';
import '../widgets/platform_badge.dart';

/// One save in full: title, where it came from, which folder and who filed
/// it, the summary and who wrote it, the link. Reached from the item menu's
/// "Details" (tapping a row opens the original post instead). Opening the
/// source stays the main action here too.
class ItemDetailScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Item item;
  final ItemCallbacks callbacks;
  const ItemDetailScreen({super.key, required this.apiClient, required this.item, required this.callbacks});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late Item _item = widget.item;

  // Changes made here update this screen AND the list behind it.
  late final _cb = ItemCallbacks(
    onChanged: (it) {
      if (mounted) setState(() => _item = it);
      widget.callbacks.onChanged(it);
    },
    onDeleted: widget.callbacks.onDeleted,
  );

  String get _folderSub {
    final it = _item;
    if (!it.processed && it.waitingForAi) return 'Fetch is picking a folder';
    if (it.suggestionWaiting) return 'Fetch suggests a new "${it.folderSuggestion}" folder';
    if (it.folderId != null && it.folderBy == 'ai') return 'Filed by Fetch';
    if (it.folderId != null) return 'Filed by you';
    return 'Not in a folder yet';
  }

  Future<void> _delete() async {
    if (await deleteItem(context, widget.apiClient, _item, _cb) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final it = _item;
    final meta = [
      it.platformName,
      if (it.author != null) it.author!,
      'Saved ${timeAgo(it.createdAt, DateTime.now()).toLowerCase()}',
    ].join(' · ');

    final Widget summary;
    if (!it.processed) {
      summary = _Block(label: 'Summary', tag: 'Organizing…', child: const LinearProgressIndicator());
    } else if (!it.hasContent && !it.editedByUser) {
      summary = Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Fetch could only read the link, not the post itself, so there's no summary. "
                'Add a title so search can find it.'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => editItem(context, widget.apiClient, it, _cb),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Add a title'),
            ),
          ]),
        ),
      );
    } else {
      summary = _Block(
        label: 'Summary',
        tag: it.editedByUser ? 'Edited by you' : 'Written by AI',
        child: Text(it.summary ?? "The AI summary didn't come through this time.", style: theme.textTheme.bodyMedium),
      );
    }

    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(tooltip: 'Share link', icon: const Icon(Icons.share_outlined), onPressed: () => shareItem(it)),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        Center(child: PlatformBadge(platform: it.platformKey, size: 84)),
        const SizedBox(height: 16),
        Text(it.displayTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(meta, style: muted),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(it.folderName ?? 'Unsorted'),
            subtitle: Text(_folderSub),
            trailing: TextButton(
              onPressed: () => moveItem(context, widget.apiClient, it, _cb),
              child: const Text('Change'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        summary,
        const SizedBox(height: 16),
        _Block(
          label: 'Link',
          child: Row(children: [
            const Icon(Icons.link, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(it.url, style: muted)),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openLink(context, it.url),
                icon: const Icon(Icons.open_in_new),
                label: Text(it.openLabel),
              ),
            ),
            IconButton(
              tooltip: 'Edit title and summary',
              icon: const Icon(Icons.edit_outlined),
              onPressed: it.processed ? () => editItem(context, widget.apiClient, it, _cb) : null,
            ),
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ]),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final String label;
  final String? tag;
  final Widget child;
  const _Block({required this.label, this.tag, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: theme.textTheme.labelLarge),
        if (tag != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(tag!, style: theme.textTheme.labelSmall),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      child,
    ]);
  }
}
