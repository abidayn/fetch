import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../logic/library.dart';
import '../models/folder.dart';
import '../models/item.dart';
import '../util/open_link.dart';
import '../widgets/folder_picker.dart' show kAiAccent;
import '../widgets/item_actions.dart';
import '../widgets/item_row.dart';

/// Time range options for the `created_after` filter. Relative to today,
/// because "what I saved last week" is more natural than picking a date.
enum _TimeRange {
  any('Any time', null),
  week('Last 7 days', 7),
  month('Last 30 days', 30),
  year('Last year', 365);

  final String label;
  final int? days;
  const _TimeRange(this.label, this.days);

  DateTime? get createdAfter => days == null ? null : DateTime.now().subtract(Duration(days: days!));
}

const _suggestions = ['that pasta video', 'postgres index tutorial', 'things to do in Tokyo', 'salary negotiation tips'];

/// Search and ask. Folder names match on every keystroke (on the phone,
/// free); search by meaning runs on Enter (one embedding call each); the AI
/// answer only on request (a Gemini call). Opened from inside a folder,
/// search stays in that folder until the "In X ×" chip is tapped.
class SearchScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Folder? scope;
  final ItemCallbacks callbacks;

  /// Opens a folder on home (a tapped folder match).
  final ValueChanged<String> onOpenFolder;

  const SearchScreen({
    super.key,
    required this.apiClient,
    this.scope,
    required this.callbacks,
    required this.onOpenFolder,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  // null = hasn't searched yet, [] = searched but nothing matched.
  List<SearchResult>? _results;
  String? _error;
  bool _loading = false;
  String? _lastQuery;

  late Folder? _scope = widget.scope;
  _TimeRange _range = _TimeRange.any;
  List<Folder>? _folders;

  // The answer: requested with a button, not on every search -- each one is
  // a Gemini call against a small daily quota, and the list is often enough.
  String? _answer;
  List<Item> _answerSources = const [];
  bool _answerLoading = false;
  DateTime? _answerStarted;
  Timer? _elapsed;

  // Results from an older search (the filter changed mid-request) are dropped.
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.apiClient.listFolders().then((raw) {
      final folders = raw.map((e) => Folder.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) setState(() => _folders = folders);
    }).catchError((_) {
      // Without the folder list, folder matches and the folder filter hide.
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _elapsed?.cancel();
    super.dispose();
  }

  late final _cb = ItemCallbacks(
    onChanged: (it) {
      setState(() {
        _results = [for (final r in _results ?? <SearchResult>[]) r.item.id == it.id ? SearchResult(item: it, score: r.score) : r];
      });
      widget.callbacks.onChanged(it);
    },
    onDeleted: (it) {
      setState(() {
        _results = _results?.where((r) => r.item.id != it.id).toList();
        // The [n] numbers point at the answer's sources: stale once one is gone.
        _answer = null;
      });
      widget.callbacks.onDeleted(it);
    },
  );

  Future<void> _search() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;
    final seq = ++_searchSeq;
    _focus.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _answer = null;
      _answerLoading = false;
      _lastQuery = query;
    });
    try {
      final raw = await widget.apiClient.search(query, folderId: _scope?.id, createdAfter: _range.createdAfter);
      if (!mounted || seq != _searchSeq) return;
      setState(() => _results = raw.map((e) => SearchResult.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException catch (e) {
      if (mounted && seq == _searchSeq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _searchSeq) setState(() => _loading = false);
    }
  }

  void _setScope(Folder? f) {
    setState(() => _scope = f);
    if (_lastQuery != null) _search();
  }

  void _setRange(_TimeRange r) {
    setState(() => _range = r);
    if (_lastQuery != null) _search();
  }

  Future<void> _ask() async {
    final query = _lastQuery;
    if (query == null || _answerLoading) return;
    final seq = _searchSeq;
    setState(() {
      _answerLoading = true;
      _answerStarted = DateTime.now();
    });
    _elapsed?.cancel();
    _elapsed = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _answerLoading) setState(() {});
    });
    try {
      final data = await widget.apiClient.searchAnswer(query, folderId: _scope?.id, createdAfter: _range.createdAfter);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _answer = data['answer'] as String? ?? 'The AI is unavailable right now, try again later.';
        _answerSources = [
          for (final s in data['sources'] as List<dynamic>) Item.fromJson(s as Map<String, dynamic>),
        ];
      });
    } on ApiException catch (e) {
      if (mounted && seq == _searchSeq) setState(() => _answer = e.message);
    } finally {
      _elapsed?.cancel();
      if (mounted) setState(() => _answerLoading = false);
    }
  }

  void _openFolder(Folder f) {
    Navigator.pop(context);
    widget.onOpenFolder(f.id);
  }

  // --- pieces ---------------------------------------------------------------------

  Widget _filters() {
    final folders = _folders;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (_scope != null)
            InputChip(
              label: Text('In ${_scope!.name}'),
              selected: true,
              onDeleted: () => _setScope(null),
              onPressed: () => _setScope(null),
              tooltip: 'Searching in ${_scope!.name}. Tap to search all folders',
            )
          else if (folders != null && folders.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Search in one folder',
              onSelected: (id) => _setScope(folders.firstWhere((f) => f.id == id)),
              itemBuilder: (_) => [for (final f in byName(folders)) PopupMenuItem(value: f.id, child: Text(f.name))],
              child: const Chip(label: Text('All folders'), avatar: Icon(Icons.arrow_drop_down)),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<_TimeRange>(
            tooltip: 'Filter by date saved',
            onSelected: _setRange,
            itemBuilder: (_) => [for (final r in _TimeRange.values) PopupMenuItem(value: r, child: Text(r.label))],
            child: Chip(label: Text(_range.label), avatar: const Icon(Icons.arrow_drop_down)),
          ),
        ],
      ),
    );
  }

  /// Folder names matching what's typed, live. Tapping one opens it on home.
  List<Widget> _live(ThemeData theme) {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return const [];
    final matches = filterFolders(byName(_folders ?? const []), q);
    return [
      if (matches.isNotEmpty) ...[
        _head(theme, 'Folders', '${matches.length}'),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in matches)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text('${f.name} ${f.itemCount}'),
                    tooltip: 'Open folder',
                    onPressed: () => _openFolder(f),
                  ),
                ),
            ],
          ),
        ),
      ],
      if (q != _lastQuery)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text('Press Enter to search ${_scope != null ? '${_scope!.name} ' : 'your saves '}by meaning.',
              style: theme.textTheme.bodySmall),
        ),
    ];
  }

  Widget _head(ThemeData theme, String title, [String? trailing]) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
          if (trailing != null) Text(trailing, style: theme.textTheme.bodySmall),
        ]),
      );

  Widget _answerArea(ThemeData theme, int resultCount) {
    final top = resultCount < 3 ? resultCount : 3;
    if (_answerLoading) {
      final secs = DateTime.now().difference(_answerStarted ?? DateTime.now()).inSeconds;
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Reading your top $top saves…', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Usually 5–25 seconds', style: theme.textTheme.bodySmall)),
              Text('$secs s', style: theme.textTheme.bodySmall),
            ]),
          ]),
        ),
      );
    }
    final answer = _answer;
    if (answer == null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: ListTile(
          leading: const Icon(Icons.auto_awesome, color: kAiAccent),
          title: const Text('Answer from these saves'),
          subtitle: Text('Fetch reads your top $top and writes a short answer'),
          onTap: _ask,
        ),
      );
    }
    final parts = parseAnswer(answer, _answerSources.length);
    final cited = citedSources(parts);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (cited.isNotEmpty)
            Text('From ${cited.length} of your saves · written by AI', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Text.rich(TextSpan(style: theme.textTheme.bodyMedium, children: [
            for (final p in parts)
              if (p.text != null)
                TextSpan(text: p.text)
              else
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _CiteButton(n: p.cite!, onTap: () => openLink(context, _answerSources[p.cite! - 1].url)),
                ),
          ])),
          if (cited.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final n in cited)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: _CiteButton(n: n, onTap: () => openLink(context, _answerSources[n - 1].url)),
                title: Text(_answerSources[n - 1].displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => openLink(context, _answerSources[n - 1].url),
              ),
          ],
        ]),
      ),
    );
  }

  List<Widget> _body(ThemeData theme) {
    if (_loading) return const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))];
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _search, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ]),
        ),
      ];
    }
    final results = _results;
    if (results == null) {
      if (_ctrl.text.trim().isNotEmpty) return const [];
      return [
        _head(theme, 'Try'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final s in _suggestions)
              ActionChip(
                label: Text(s),
                onPressed: () {
                  _ctrl.text = s;
                  _search();
                },
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            "Search looks for meaning, not exact words. Describe what it was about, like you'd tell a friend.",
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ];
    }
    if (results.isEmpty) {
      final where = _scope != null ? 'in ${_scope!.name}' : 'in your saves';
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text('Nothing matched', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Nothing $where is about "$_lastQuery". Try describing it differently.', textAlign: TextAlign.center),
            if (_scope != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: () => _setScope(null), child: const Text('Search all folders')),
            ],
          ]),
        ),
      ];
    }
    return [
      _answerArea(theme, results.length),
      _head(theme, '${results.length} save${results.length == 1 ? '' : 's'} match', 'Best match first'),
      for (final r in results) ...[
        ItemRow(key: ValueKey(r.item.id), apiClient: widget.apiClient, item: r.item, callbacks: _cb),
        const Divider(height: 1, indent: 72),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) => setState(() {}), // refresh the live folder matches
          decoration: const InputDecoration(hintText: 'Search or ask your saves', border: InputBorder.none),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _ctrl.clear();
                _results = null;
                _lastQuery = null;
                _answer = null;
                _focus.requestFocus();
              }),
            ),
        ],
      ),
      body: ListView(children: [
        _filters(),
        ..._live(theme),
        ..._body(theme),
      ]),
    );
  }
}

class _CiteButton extends StatelessWidget {
  final int n;
  final VoidCallback onTap;
  const _CiteButton({required this.n, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Source $n',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
          child: Text('$n', style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
