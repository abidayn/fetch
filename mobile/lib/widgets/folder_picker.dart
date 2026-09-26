import 'package:flutter/material.dart';

import '../models/folder.dart';
import '../models/item.dart';

// The AI option's own colour, so "Let AI pick" reads as different from the
// user's folders. A placeholder until the redesign moves it into the theme.
const kAiAccent = Color(0xFF7B3FE4);
const kAiContainer = Color(0xFFF1EAFD);
const kOnAiContainer = Color(0xFF3B1778);

/// "Choose a folder": the "Let AI pick" card first (in the AI colour), then
/// the user's folders, then "+ New folder".
///
/// Stateless: the parent (save_result_sheet.dart) owns the item and the
/// folder list, sends the choice to the backend and passes the result back
/// in (only the "Find a folder" text lives in _FolderGrid below). The item's
/// folder fields say what's selected:
/// - folderBy 'ai'   -> the AI card (plus the folder it placed the item in)
/// - folderBy 'user' -> that folder card
/// - folderBy null   -> nothing (the item stays Unfiled)
class FolderPicker extends StatelessWidget {
  final Item item;

  /// null = still loading.
  final List<Folder>? folders;
  final String? foldersError;
  final VoidCallback? onRetryFolders;

  /// The backend is still working on "Let AI pick" (the parent knows, since
  /// it polls; it also stops waiting after a while).
  final bool aiWorking;

  final VoidCallback onPickAi;
  final ValueChanged<Folder> onPickFolder;

  /// "+ New folder": gets the name typed in "Find a folder" when nothing
  /// matched it (to pre-fill the name dialog), otherwise ''.
  final ValueChanged<String> onCreate;

  const FolderPicker({
    super.key,
    required this.item,
    required this.folders,
    this.foldersError,
    this.onRetryFolders,
    this.aiWorking = false,
    required this.onPickAi,
    required this.onPickFolder,
    required this.onCreate,
  });

  bool get _aiSelected => item.folderBy == 'ai';

  /// The AI can't suggest anything for a link it couldn't read.
  bool get _aiImpossible => item.processed && !item.hasContent && item.folderSuggestion == null;

  bool get _aiBusy => _aiSelected && item.folderId == null && aiWorking;

  String _aiSubtitle() {
    final suggestion = item.folderSuggestion;
    if (_aiSelected) {
      if (item.folderId != null) return 'Put it in ${item.folderName ?? 'a folder'}';
      if (_aiBusy) return 'Choosing a folder…';
      if (!item.processed) return "Still working on it. It'll be filed when it's ready.";
      if (!item.hasContent) return "Can't read this link, so the AI can't choose. Pick a folder below.";
      return "The AI couldn't choose this time. Pick a folder below.";
    }
    if (!item.processed) {
      return (folders?.isEmpty ?? false)
          ? 'No folders yet. The AI will name one for this link.'
          : 'Chooses as soon as the link is read';
    }
    if (suggestion != null) {
      final exists = folders?.any((f) => f.name.toLowerCase() == suggestion.toLowerCase()) ?? false;
      return exists ? 'Suggests $suggestion' : 'Suggests a new folder: $suggestion';
    }
    if (_aiImpossible) return "Can't read this link";
    return 'Asks the AI to choose a folder';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('Choose a folder', style: theme.textTheme.titleSmall)),
          Text('Optional', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 10),
        _aiCard(theme),
        const SizedBox(height: 10),
        _folderGrid(theme),
        if (item.folderBy == null) ...[
          const SizedBox(height: 8),
          Text(
            'Skip this and it stays in Unfiled.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _aiCard(ThemeData theme) {
    final selected = _aiSelected;
    final enabled = !_aiImpossible || selected;
    final Widget trailing;
    if (_aiBusy) {
      trailing = const SizedBox(
          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: kAiAccent));
    } else if (selected && item.folderId != null) {
      trailing = const Icon(Icons.check_circle, color: kAiAccent);
    } else {
      trailing = Icon(Icons.radio_button_unchecked, color: kAiAccent.withValues(alpha: 0.5));
    }

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFFE6D9FC) : kAiContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? kAiAccent : kAiAccent.withValues(alpha: 0.35), width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled && !selected ? onPickAi : null,
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
                  Text('Let AI pick',
                      style: theme.textTheme.titleSmall?.copyWith(color: kOnAiContainer, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_aiSubtitle(), style: theme.textTheme.bodySmall?.copyWith(color: kOnAiContainer)),
                ]),
              ),
              const SizedBox(width: 8),
              trailing,
            ]),
          ),
        ),
      ),
    );
  }

  Widget _folderGrid(ThemeData theme) {
    final list = folders;
    if (list == null) {
      if (foldersError != null) {
        return Row(children: [
          Expanded(child: Text("Couldn't load your folders: $foldersError", style: theme.textTheme.bodySmall)),
          if (onRetryFolders != null) TextButton(onPressed: onRetryFolders, child: const Text('Retry')),
        ]);
      }
      return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
    }
    // The folder the AI just created may not be in the list the sheet loaded
    // yet (it reloads it) -- show it anyway, so the selection is visible.
    final shown = [...list];
    if (item.folderId != null && !shown.any((f) => f.id == item.folderId)) {
      shown.insert(0, Folder(id: item.folderId!, name: item.folderName ?? 'Folder', itemCount: 1));
    }
    return _FolderGrid(folders: shown, item: item, onPickFolder: onPickFolder, onCreate: onCreate);
  }
}

/// Above this many folders, the grid gets a "Find a folder" box. Below it the
/// box is just clutter: every folder already fits on screen.
const kFolderSearchThreshold = 6;

/// The folder cards plus "+ New folder" -- and, with many folders, a box that
/// filters them by name (filterFolders). Stateful only to hold what's typed;
/// the choice itself still goes up to the sheet.
class _FolderGrid extends StatefulWidget {
  final List<Folder> folders;
  final Item item;
  final ValueChanged<Folder> onPickFolder;
  final ValueChanged<String> onCreate;
  const _FolderGrid({required this.folders, required this.item, required this.onPickFolder, required this.onCreate});

  @override
  State<_FolderGrid> createState() => _FolderGridState();
}

class _FolderGridState extends State<_FolderGrid> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchable = widget.folders.length > kFolderSearchThreshold;
    final query = searchable ? _ctrl.text.trim() : '';
    final shown = filterFolders(widget.folders, query);
    // Searched and found nothing: offer to create exactly what was typed.
    final createName = query.isNotEmpty && shown.isEmpty ? query : '';
    final item = widget.item;

    const gap = 10.0;
    final grid = LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 2 * gap) / 3;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final f in shown)
          SizedBox(
            width: width,
            child: _FolderCard(
              folder: f,
              selected: f.id == item.folderId,
              byAi: f.id == item.folderId && item.folderBy == 'ai',
              onTap: () => widget.onPickFolder(f),
            ),
          ),
        SizedBox(width: width, child: _NewFolderCard(name: createName, onTap: () => widget.onCreate(createName))),
      ]);
    });
    if (!searchable) return grid;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Find a folder',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_ctrl.clear),
                ),
        ),
      ),
      const SizedBox(height: 10),
      grid,
    ]);
  }
}

class _FolderCard extends StatelessWidget {
  final Folder folder;
  final bool selected;
  final bool byAi;
  final VoidCallback onTap;
  const _FolderCard({required this.folder, required this.selected, required this.byAi, required this.onTap});

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
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.folder_outlined, size: 20, color: scheme.primary),
                  const Spacer(),
                  if (byAi)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: kAiAccent, borderRadius: BorderRadius.circular(8)),
                      child: const Text('AI',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    )
                  else if (selected)
                    Icon(Icons.check_circle, size: 18, color: scheme.primary),
                ]),
                const SizedBox(height: 6),
                Text(folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(count == 1 ? '1 item' : '$count items',
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
  /// Non-empty = the searched name nothing matched: 'Create "name"'.
  final String name;
  final VoidCallback onTap;
  const _NewFolderCard({this.name = '', required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, color: scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(
                name.isEmpty ? 'New folder' : 'Create "$name"',
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
