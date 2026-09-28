import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../logic/library.dart';
import '../models/folder.dart';
import '../models/item.dart';
import '../util/app_channel.dart';
import 'folder_name_dialog.dart';
import 'folder_picker.dart';
import 'platform_badge.dart';

/// The save sheet, shown right after a link is saved (the 201 has already
/// come back, so closing it never loses the link). Stages:
///
///   pick        "Where should it go?" -- Let Fetch pick, a folder, or +.
///               Closing the sheet here counts as "Let Fetch pick".
///   organizing  Saved → Reading the link → Writing a summary → Picking a
///               folder (or "Going to X"). The steps are timed: the backend
///               only reports processed yes/no. You can leave any time.
///   done        "All set": the result, where it went and who picked it, Change.
///   needsFolder Fetch couldn't read the link (or couldn't pick): pick one,
///               or leave it in Unsorted.
///   suggest     None of the folders fit: create Fetch's proposed folder,
///               pick another, or leave it in Unsorted.
///   repick      After "Change" / "Pick a folder".
///
/// [fromShare]: opened by Android's share menu, so the footer offers "Back
/// to TikTok" (and "Open in Fetch"); a link pasted inside Fetch just gets Done.
/// [onChanged] receives every confirmed version of the item; [onToast]
/// shows a message after the sheet has gone (a snackbar under a sheet would
/// be hidden).
Future<void> showSaveResultSheet(
  BuildContext context,
  ApiClient apiClient,
  Item item, {
  bool fromShare = false,
  ValueChanged<Item>? onChanged,
  ValueChanged<String>? onToast,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SaveSheet(
      apiClient: apiClient,
      initial: item,
      fromShare: fromShare,
      onChanged: onChanged,
      onToast: onToast,
    ),
  );
}

enum _Stage { pick, organizing, done, needsFolder, suggest, repick }

class _SaveSheet extends StatefulWidget {
  final ApiClient apiClient;
  final Item initial;
  final bool fromShare;
  final ValueChanged<Item>? onChanged;
  final ValueChanged<String>? onToast;
  const _SaveSheet({
    required this.apiClient,
    required this.initial,
    required this.fromShare,
    this.onChanged,
    this.onToast,
  });

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  // Enrichment normally takes 4-9 s, up to ~20 s when Gemini retries. After
  // 60 s the sheet stops waiting; the item still updates itself in the list.
  static const _pollInterval = Duration(seconds: 3);
  static const _maxWait = Duration(seconds: 60);

  late Item _item = widget.initial;
  List<Folder>? _folders;
  String? _foldersError;
  String? _error;

  /// null = nothing chosen yet; 'ai'; 'unsorted'; or a folder id.
  String? _choice;
  bool _repick = false;
  DateTime? _chosenAt;

  Timer? _poll;
  Timer? _tick; // re-renders the timed progress steps
  DateTime? _deadline;
  bool _gaveUp = false;
  int _version = 0; // replies/polls from an older choice are dropped

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _schedulePoll();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    if (_choice == null) {
      // Closed without choosing = "Let Fetch pick" (the prototype's rule: a
      // save always ends up filed, or flagged in Needs you -- never silently
      // lost in Unsorted). Fire and forget: the list picks up the result.
      widget.apiClient.setItemFolder(_item.id, ai: true).then((json) {
        widget.onChanged?.call(Item.fromJson(json));
      }).catchError((_) {});
      widget.onToast?.call('Saved. Fetch will pick a folder.');
    }
    super.dispose();
  }

  bool get _aiWorking =>
      _item.waitingForAi &&
      (!_item.processed || (_item.hasContent && _item.summary != null && _item.folderSuggestion == null));

  bool get _needsPoll => !_item.processed || (_choice == 'ai' && _aiWorking);

  _Stage get _stage {
    if (_repick) return _Stage.repick;
    if (_choice == null) return _Stage.pick;
    if (!_item.processed) return _Stage.organizing;
    if (_choice != 'ai') return _Stage.done;
    if (_item.folderId != null) return _Stage.done;
    if (_item.suggestionWaiting) return _Stage.suggest;
    if (_item.hasContent && _aiWorking && !_gaveUp) return _Stage.organizing;
    return _Stage.needsFolder;
  }

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
    if (_poll != null || !_needsPoll) return;
    _deadline ??= DateTime.now().add(_maxWait);
    if (DateTime.now().isAfter(_deadline!)) {
      setState(() => _gaveUp = true);
      return;
    }
    _poll = Timer(_pollInterval, _pollOnce);
  }

  Future<void> _pollOnce() async {
    _poll = null;
    final version = _version;
    try {
      final fresh = Item.fromJson(await widget.apiClient.getItem(_item.id));
      if (!mounted || version != _version) return;
      _setItem(fresh);
    } catch (_) {
      // Brief network glitch: try again on the next round.
    }
    if (mounted) _schedulePoll();
  }

  void _setItem(Item fresh) {
    setState(() => _item = fresh);
    widget.onChanged?.call(fresh);
  }

  void _startTicking() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _stage != _Stage.organizing) {
        _tick?.cancel();
        return;
      }
      setState(() {});
    });
  }

  /// Sends one folder decision. [choice] is what the sheet shows meanwhile.
  Future<void> _send(String choice, {Folder? folder, bool ai = false, bool accept = false}) async {
    final version = ++_version;
    setState(() {
      _choice = choice;
      _repick = false;
      _error = null;
      _chosenAt ??= DateTime.now();
      if (ai) {
        _deadline = null;
        _gaveUp = false;
      }
    });
    _startTicking();
    try {
      final json = await widget.apiClient.setItemFolder(
        _item.id,
        ai: ai,
        acceptSuggestion: accept,
        folderId: folder?.id,
      );
      if (!mounted || version != _version) return;
      _setItem(Item.fromJson(json));
      _loadFolders(); // counts changed; accepting may have created a folder
      _schedulePoll();
    } on ApiException catch (e) {
      if (!mounted || version != _version) return;
      // Inline, not a snackbar: a snackbar would appear behind this sheet.
      setState(() => _error = "Couldn't save the folder: ${e.message}");
    }
  }

  void _pickFolder(Folder f) => _send(f.id, folder: f);

  Future<void> _createFolder(String initial) async {
    final name = await showFolderNameDialog(context, initial: initial);
    if (name == null || !mounted) return;
    try {
      final folder = Folder.fromJson(await widget.apiClient.createFolder(name));
      if (!mounted) return;
      setState(() => _folders = [...?_folders, folder]);
      await _send(folder.id, folder: folder);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = "Couldn't create the folder: ${e.message}");
    }
  }

  Future<void> _backToSource() async {
    Navigator.pop(context);
    await moveAppToBack();
  }

  // --- pieces ------------------------------------------------------------------

  Widget _head(ThemeData theme, String title, {bool ok = true}) {
    return Row(children: [
      PlatformBadge(platform: _item.platformKey, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (ok) ...[Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary), const SizedBox(width: 6)],
            Flexible(child: Text(title, style: theme.textTheme.titleLarge)),
          ]),
          Text(_item.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    ]);
  }

  Widget _result(ThemeData theme) {
    if (!_item.hasContent) {
      return Text("Only the link could be read, so there's no summary. You can add a title later.",
          style: theme.textTheme.bodyMedium);
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          if (_item.summary != null) ...[
            const SizedBox(height: 4),
            Text(_item.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ] else ...[
            const SizedBox(height: 4),
            Text("The AI summary didn't come through this time.", style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }

  Widget _steps(ThemeData theme) {
    final elapsed = DateTime.now().difference(_chosenAt ?? DateTime.now()).inSeconds;
    final manual = _choice != 'ai';
    final folderName = _item.folderName ?? (_choice == 'unsorted' ? 'Unsorted' : null);
    // Timed: "Reading" for the first ~3 s, then "Writing". The real finish
    // comes from polling (the stage moves on when the item is processed).
    final reading = elapsed < 3;
    Widget step(String label, {required bool done, bool now = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 20,
              height: 20,
              child: done
                  ? Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary)
                  : now
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(Icons.radio_button_unchecked, size: 20, color: theme.colorScheme.outline),
            ),
            const SizedBox(width: 10),
            Text(label, style: now ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : null),
          ]),
        );
    final processed = _item.processed;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      step('Saved', done: true),
      step('Reading the link', done: processed || !reading, now: !processed && reading),
      step('Writing a title and summary', done: processed, now: !processed && !reading),
      manual
          ? step('Going to ${folderName ?? 'your folder'}', done: true)
          : step('Picking a folder', done: false, now: processed),
    ]);
  }

  Widget _filedRow(ThemeData theme) {
    final name = _item.folderName ?? 'Unsorted';
    final by = _item.folderId == null
        ? 'Not in a folder'
        : _item.folderBy == 'ai'
            ? 'Picked by Fetch'
            : 'Picked by you';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(name),
        subtitle: Text(by, style: _item.folderBy == 'ai' ? const TextStyle(color: kAiAccent) : null),
        trailing: TextButton(onPressed: () => setState(() => _repick = true), child: const Text('Change')),
      ),
    );
  }

  Widget _footer() {
    if (!widget.fromShare) {
      return FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'));
    }
    final source = sourceAppName(_item.url);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton(onPressed: _backToSource, child: Text(source == null ? 'Go back' : 'Back to $source')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Open in Fetch')),
    ]);
  }

  Widget _picker({bool ai = false, String? selected}) => FolderPicker(
        folders: _folders,
        foldersError: _foldersError,
        onRetryFolders: _loadFolders,
        selectedId: selected,
        showAi: ai,
        onPickAi: () => _send('ai', ai: true),
        onPickFolder: _pickFolder,
        onCreate: _createFolder,
      );

  Widget _hint(ThemeData theme, String text) =>
      Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = const SizedBox(height: 16);
    final List<Widget> children;
    switch (_stage) {
      case _Stage.pick:
        children = [
          _head(theme, 'Saved to Fetch'),
          gap,
          Text('Where should it go?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          _picker(ai: true),
          const SizedBox(height: 10),
          _hint(theme, 'Close this and Fetch will pick.'),
        ];
      case _Stage.organizing:
        children = [
          _head(theme, 'Saved to Fetch'),
          gap,
          _steps(theme),
          const SizedBox(height: 8),
          _hint(theme, 'You can leave now. Fetch keeps working.'),
          gap,
          _footer(),
        ];
      case _Stage.done:
        children = [
          _head(theme, 'All set'),
          gap,
          _result(theme),
          const SizedBox(height: 12),
          _filedRow(theme),
          gap,
          _footer(),
        ];
      case _Stage.needsFolder:
        final source = sourceAppName(_item.url) ?? 'The page';
        children = [
          _head(theme, _item.hasContent ? "Saved, but Fetch couldn't pick" : "Saved, but Fetch couldn't read it",
              ok: false),
          gap,
          Text(
            _item.hasContent
                ? "Fetch couldn't choose a folder this time. Pick one for it."
                : "$source only shared the link, so Fetch can't tell what it's about. Pick a folder for it.",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _picker(),
          const SizedBox(height: 8),
          TextButton(onPressed: () => _send('unsorted'), child: const Text('Leave it in Unsorted')),
        ];
      case _Stage.suggest:
        children = [
          _head(theme, 'Saved to Fetch'),
          gap,
          _result(theme),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            color: kAiContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('None of your folders fit this.', style: theme.textTheme.bodySmall?.copyWith(color: kOnAiContainer)),
                const SizedBox(height: 4),
                Text('Create a "${_item.folderSuggestion}" folder for it?',
                    style: theme.textTheme.titleSmall?.copyWith(color: kOnAiContainer)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kAiAccent),
                      onPressed: () => _send('ai', accept: true),
                      child: const Text('Create folder'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                        onPressed: () => setState(() => _repick = true), child: const Text('Pick a folder')),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: () => _send('unsorted'), child: const Text('Leave it in Unsorted')),
        ];
      case _Stage.repick:
        children = [
          Text('Pick a folder', style: theme.textTheme.titleLarge),
          gap,
          _picker(selected: _item.folderId),
          const SizedBox(height: 8),
          TextButton(onPressed: () => setState(() => _repick = false), child: const Text('Cancel')),
        ];
    }

    return SingleChildScrollView(
      // Bottom inset: with many folders the picker has a "Find a folder" box,
      // and the keyboard it opens must not cover it.
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...children,
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ]),
    );
  }
}
