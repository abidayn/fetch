import 'package:flutter/material.dart';

import '../models/folder.dart';

// The AI option's own colour, so "Let Fetch pick" reads as different from the
// user's folders. A placeholder until the redesign moves it into the theme.
const kAiAccent = Color(0xFF7B3FE4);
const kAiContainer = Color(0xFFF1EAFD);
const kOnAiContainer = Color(0xFF3B1778);

/// Above this many folders, the picker gets a "Find a folder" box. Below it
/// the box is just clutter: every folder already fits on screen.
const kFolderSearchThreshold = 6;

/// Where a save goes: "Let Fetch pick" first (only when [showAi], i.e. the
/// save sheet's first step), then the user's folders most recently used
/// first, then "+ New folder". With many folders a "Find a folder" box
/// filters them; when nothing matches, "+" offers to create what was typed.
///
/// Holds only the typed search text; the choice goes straight up to the
/// parent, which talks to the backend.
class FolderPicker extends StatefulWidget {
  /// null = still loading.
  final List<Folder>? folders;
  final String? foldersError;
  final VoidCallback? onRetryFolders;

  /// The folder shown as selected (the item's current folder), if any.
  final String? selectedId;
  final bool showAi;
  final VoidCallback? onPickAi;
  final ValueChanged<Folder> onPickFolder;

  /// "+ New folder": gets the name typed in "Find a folder" when nothing
  /// matched it (to pre-fill the name dialog), otherwise ''.
  final ValueChanged<String> onCreate;

  const FolderPicker({
    super.key,
    required this.folders,
    this.foldersError,
    this.onRetryFolders,
    this.selectedId,
    this.showAi = false,
    this.onPickAi,
    required this.onPickFolder,
    required this.onCreate,
  });

  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  final _find = TextEditingController();

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showAi) ...[
        _AiOption(onTap: widget.onPickAi),
        const SizedBox(height: 10),
      ],
      _grid(theme),
    ]);
  }

  Widget _grid(ThemeData theme) {
    final list = widget.folders;
    if (list == null) {
      if (widget.foldersError != null) {
        return Row(children: [
          Expanded(child: Text("Couldn't load your folders: ${widget.foldersError}", style: theme.textTheme.bodySmall)),
          if (widget.onRetryFolders != null) TextButton(onPressed: widget.onRetryFolders, child: const Text('Retry')),
        ]);
      }
      return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
    }

    final searchable = list.length > kFolderSearchThreshold;
    final query = searchable ? _find.text.trim() : '';
    final shown = filterFolders(byRecent(list), query);
    // Searched and found nothing: offer to create exactly what was typed.
    final createName = query.isNotEmpty && shown.isEmpty ? query : '';

    const gap = 10.0;
    final grid = LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 2 * gap) / 3;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final f in shown)
          SizedBox(
            width: width,
            child: _FolderCard(folder: f, selected: f.id == widget.selectedId, onTap: () => widget.onPickFolder(f)),
          ),
        SizedBox(width: width, child: _NewFolderCard(name: createName, onTap: () => widget.onCreate(createName))),
      ]);
    });
    if (!searchable) return grid;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _find,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Find a folder',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _find.text.isEmpty
              ? null
              : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => setState(_find.clear)),
        ),
      ),
      if (query.isNotEmpty && shown.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('No folder with that name.', style: theme.textTheme.bodySmall),
        ),
      const SizedBox(height: 10),
      grid,
    ]);
  }
}

class _AiOption extends StatelessWidget {
  final VoidCallback? onTap;
  const _AiOption({this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: kAiContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kAiAccent.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: kAiAccent, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Let Fetch pick',
                    style: theme.textTheme.titleSmall?.copyWith(color: kOnAiContainer, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Fetch reads the link and files it where it fits. Takes a few seconds.',
                    style: theme.textTheme.bodySmall?.copyWith(color: kOnAiContainer)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final Folder folder;
  final bool selected;
  final VoidCallback onTap;
  const _FolderCard({required this.folder, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = folder.itemCount;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.folder_outlined, size: 20, color: scheme.primary),
                  const Spacer(),
                  if (selected) Icon(Icons.check_circle, size: 18, color: scheme.primary),
                ]),
                const SizedBox(height: 6),
                Text(folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(count == 1 ? '1 save' : '$count saves',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewFolderCard extends StatelessWidget {
  /// Non-empty = the searched name nothing matched: 'New folder "name"'.
  final String name;
  final VoidCallback onTap;
  const _NewFolderCard({this.name = '', required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, color: scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(
                name.isEmpty ? 'New folder' : 'New folder "$name"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
