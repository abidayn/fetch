import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/folder.dart';
import '../models/item.dart';
import 'folder_name_dialog.dart';
import 'folder_picker.dart';

/// Feedback after a link is saved: "Saved — AI is organizing this…", which
/// turns into the AI result once enrichment finishes on the backend -- plus
/// the folder picker (FolderPicker). Choosing a folder is optional; closing
/// the sheet without one leaves the item Unfiled.
Future<void> showSaveResultSheet(BuildContext context, ApiClient apiClient, Item item) {
  return _showItemSheet(context, apiClient, item, justSaved: true);
}

/// "Move to folder" for an item saved earlier: the same picker, without the
/// "Saved" feedback. [onChanged] gets every confirmed change, so the list
/// behind the sheet stays in sync however the sheet is closed.
Future<void> showFolderSheet(BuildContext context, ApiClient apiClient, Item item,
    {ValueChanged<Item>? onChanged}) {
  return _showItemSheet(context, apiClient, item, justSaved: false, onChanged: onChanged);
}

Future<void> _showItemSheet(BuildContext context, ApiClient apiClient, Item item,
    {required bool justSaved, ValueChanged<Item>? onChanged}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // The picker can be taller than the default half-screen limit.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ItemSheet(apiClient: apiClient, initial: item, justSaved: justSaved, onChanged: onChanged),
  );
}

class _ItemSheet extends StatefulWidget {
  final ApiClient apiClient;
  final Item initial;
  final bool justSaved;
  final ValueChanged<Item>? onChanged;
  const _ItemSheet({required this.apiClient, required this.initial, required this.justSaved, this.onChanged});

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  // Enrichment normally takes 4-9 seconds, but can take ~20 seconds when
  // Gemini is retrying (429/503). After 60 seconds the sheet stops waiting --
  // the item still updates itself in the home list. The same limit applies
  // to waiting for "Let AI pick" to place the item.
  static const _pollInterval = Duration(seconds: 3);
  static const _maxWait = Duration(seconds: 60);

  late Item _item = widget.initial;
  Timer? _timer;
  DateTime? _deadline;
  bool _gaveUp = false; // stopped waiting for enrichment
  bool _aiTimedOut = false; // stopped waiting for the AI to place the item

  List<Folder>? _folders;
  String? _foldersError;
  String? _choiceError;

  // Every folder choice bumps this. A reply (or poll) that belongs to an
  // older choice is dropped instead of overwriting a newer one.
  int _version = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _schedulePoll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The user tapped "Let AI pick" and the backend is still working on it:
  /// enrichment hasn't finished, or (for an item saved before folders
  /// existed) it's asking the AI right now. Not when the AI can't or didn't
  /// answer -- then there's nothing to wait for.
  bool get _aiWorking =>
      _item.waitingForAi &&
      (!_item.processed || (_item.hasContent && _item.summary != null && _item.folderSuggestion == null));

  bool get _needsPoll => !_item.processed || _aiWorking;

  Future<void> _loadFolders() async {
    try {
      final raw = await widget.apiClient.listFolders();
      if (!mounted) return;
      setState(() {
        _folders = raw.map((e) => Folder.fromJson(e as Map<String, dynamic>)).toList();
        _foldersError = null;
      });
    } on ApiException catch (e) {
      if (mounted && _folders == null) setState(() => _foldersError = e.message);
    }
  }

  void _schedulePoll() {
    if (_timer != null || !_needsPoll) return;
    _deadline ??= DateTime.now().add(_maxWait);
    if (DateTime.now().isAfter(_deadline!)) {
      setState(() {
        if (!_item.processed) _gaveUp = true;
        _aiTimedOut = true;
      });
      return;
    }
    _timer = Timer(_pollInterval, _poll);
  }

  Future<void> _poll() async {
    _timer = null;
    final version = _version;
    final startedWhileSaving = _saving;
    try {
      final fresh = Item.fromJson(await widget.apiClient.getItem(_item.id));
      if (!mounted) return;
      // A GET that overlapped a folder choice may return the row as it was
      // BEFORE that choice -- the choice's own reply is the authority.
      if (version == _version && !startedWhileSaving && !_saving) {
        final newlyPlaced = fresh.folderId != null && fresh.folderId != _item.folderId;
        setState(() => _item = fresh);
        widget.onChanged?.call(fresh);
        if (newlyPlaced) _loadFolders(); // the AI may have just created a folder
      }
    } catch (_) {
      // Brief network glitch: try again on the next round.
    }
    if (mounted) _schedulePoll();
  }

  Future<void> _choose({Folder? folder, bool ai = false}) async {
    final before = _item;
    final version = ++_version;
    setState(() {
      _saving = true;
      _choiceError = null;
      // Shown right away; the backend's reply below replaces it.
      _item = ai
          ? _item.withFolder(folderBy: 'ai')
          : folder == null
              ? _item.withFolder()
              : _item.withFolder(folderId: folder.id, folderName: folder.name, folderBy: 'user');
      if (ai) {
        // A new wait: give the AI its own full time limit.
        _deadline = null;
        _aiTimedOut = false;
      }
    });
    try {
      final fresh = Item.fromJson(await widget.apiClient.setItemFolder(_item.id, folderId: folder?.id, ai: ai));
      if (!mounted || version != _version) return;
      setState(() => _item = fresh);
      widget.onChanged?.call(fresh);
      _loadFolders(); // counts changed, and "Let AI pick" may have created a folder
    } on ApiException catch (e) {
      if (!mounted || version != _version) return;
      // Inline, not a snackbar: a snackbar would appear behind this sheet.
      setState(() {
        _item = before;
        _choiceError = "Couldn't save the folder: ${e.message}";
      });
    } finally {
      if (mounted && version == _version) {
        setState(() => _saving = false);
        _schedulePoll();
      }
    }
  }

  void _pickFolder(Folder folder) {
    // Tapping the selected folder again un-files the item.
    _choose(folder: folder.id == _item.folderId && _item.folderBy == 'user' ? null : folder);
  }

  Future<void> _createFolder() async {
    final name = await showFolderNameDialog(context);
    if (name == null || !mounted) return;
    try {
      final folder = Folder.fromJson(await widget.apiClient.createFolder(name));
      if (!mounted) return;
      setState(() => _folders = [...?_folders, folder]);
      await _choose(folder: folder);
    } on ApiException catch (e) {
      if (mounted) setState(() => _choiceError = "Couldn't create the folder: ${e.message}");
    }
  }

  Widget _savedStatus(ThemeData theme) {
    if (!_item.processed && !_gaveUp) {
      return Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text('AI is organizing this…', style: theme.textTheme.bodyMedium)),
      ]);
    }
    if (!_item.processed) {
      return Text("Still organizing — it'll update in your list when it's ready.",
          style: theme.textTheme.bodyMedium);
    }
    if (_item.summary != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_item.displayTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(_item.summary!, style: theme.textTheme.bodyMedium),
          ]),
        ),
      );
    }
    if (_item.hasContent) {
      // The link's content was read, but Gemini failed (quota/timeout).
      // Retryable on the backend (backfill_enrichment.py) -- unlike an unreadable link.
      return Text(
        "Saved, but the AI summary didn't come through this time. "
        'You can add a title and summary yourself via Edit.',
        style: theme.textTheme.bodyMedium,
      );
    }
    // Processed, but the content couldn't be read (private/deleted post, etc.).
    return Text("Couldn't read much from this link, so it's saved as-is.", style: theme.textTheme.bodyMedium);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folderName = _item.folderName;
    final String heading;
    final String subheading;
    if (widget.justSaved) {
      heading = folderName != null ? 'Saved to $folderName' : 'Saved';
      subheading = _item.url;
    } else {
      heading = 'Move to folder';
      subheading = _item.displayTitle;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(heading, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            subheading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (widget.justSaved) ...[_savedStatus(theme), const SizedBox(height: 20)],
          FolderPicker(
            item: _item,
            folders: _folders,
            foldersError: _foldersError,
            onRetryFolders: _loadFolders,
            aiWorking: _aiWorking && !_aiTimedOut,
            onPickAi: () => _choose(ai: true),
            onPickFolder: _pickFolder,
            onCreate: _createFolder,
          ),
          if (_choiceError != null) ...[
            const SizedBox(height: 8),
            Text(_choiceError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}
