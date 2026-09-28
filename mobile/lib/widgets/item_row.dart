import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../logic/library.dart';
import '../models/item.dart';
import '../util/open_link.dart';
import 'item_actions.dart';
import 'platform_badge.dart';

/// One save in a list (library, search results, Needs you).
///
/// Tap = open the original post in its app: that's why people come back.
/// Details, move, edit, share and delete sit behind ⋮ or a long-press, so
/// they aren't hit while scrolling. [below] adds content under the row --
/// Needs you puts its one-tap fixes there.
class ItemRow extends StatelessWidget {
  final ApiClient apiClient;
  final Item item;
  final ItemCallbacks callbacks;
  final Widget? below;

  const ItemRow({super.key, required this.apiClient, required this.item, required this.callbacks, this.below});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final List<Widget> body;
    if (!item.processed) {
      body = [
        Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        const SizedBox(height: 4),
        Text('Organizing…', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
      ];
    } else if (!item.hasContent && !item.editedByUser) {
      body = [
        Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text('Only the link could be read. Add a title?', style: muted),
      ];
    } else {
      body = [
        Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        if (item.summary != null) ...[
          const SizedBox(height: 2),
          Text(item.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ],
      ];
    }

    final folderLabel = !item.processed && item.waitingForAi
        ? 'Fetch is picking a folder'
        : item.folderName ?? 'Unsorted';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => openLink(context, item.url),
        onLongPress: () => showItemMenu(context, apiClient, item, callbacks),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PlatformBadge(platform: item.platformKey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...body,
                const SizedBox(height: 6),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                  Icon(PlatformBadge.iconFor(item.platformKey), size: 14, color: theme.colorScheme.onSurfaceVariant),
                  Text(item.platformName, style: muted),
                  Text('·', style: muted),
                  Text(timeAgo(item.createdAt, DateTime.now()), style: muted),
                  Text('·', style: muted),
                  _FolderPill(label: folderLabel, unsorted: item.folderId == null),
                ]),
              ]),
            ),
            IconButton(
              tooltip: 'More for ${item.displayTitle}',
              icon: const Icon(Icons.more_vert),
              onPressed: () => showItemMenu(context, apiClient, item, callbacks),
            ),
          ]),
        ),
      ),
      ?below,
    ]);
  }
}

class _FolderPill extends StatelessWidget {
  final String label;
  final bool unsorted;
  const _FolderPill({required this.label, required this.unsorted});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: unsorted ? null : scheme.secondaryContainer,
        border: unsorted ? Border.all(color: scheme.outlineVariant) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer)),
    );
  }
}
