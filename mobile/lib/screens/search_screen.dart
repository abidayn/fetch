import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../widgets/item_tile.dart';

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

class SearchScreen extends StatefulWidget {
  final ApiClient apiClient;
  const SearchScreen({super.key, required this.apiClient});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();

  // null = hasn't searched yet (show the hint), [] = searched but nothing
  // matched. Two different states, two different messages.
  List<SearchResult>? _results;
  String? _error;
  bool _loading = false;

  // Structured hybrid-search filters -- sent to the backend and applied in the
  // same SQL as the vector search, not filtered from the results in the app.
  String? _category;
  _TimeRange _range = _TimeRange.any;
  List<String>? _categories;

  // The AI answer is requested separately via a button, not automatically on
  // every search: each answer = one Gemini call (limited daily free-tier
  // quota), and often the result list alone is enough.
  String? _answer;
  bool _answerLoading = false;
  String? _lastQuery;

  // Search sequence number: results from an older search (e.g. the filter
  // changed while a request was in flight) are dropped, not allowed to
  // overwrite newer results.
  int _searchSeq = 0;

  // Menu value for "all categories". Not null: PopupMenuButton treats a null
  // choice as "cancelled" and doesn't call onSelected.
  static const _allCategories = '';

  bool get _hasFilter => _category != null || _range != _TimeRange.any;

  @override
  void initState() {
    super.initState();
    widget.apiClient.listCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {
      // Without the category list, the category filter is hidden; search still works.
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Called when the user presses enter/the search button (or changes a
  /// filter), NOT on every keystroke: each search = one embedding call to
  /// Gemini. Search-as-you-type would burn quota on meaningless word
  /// fragments ("rec", "reci", "recip").
  Future<void> _search() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;
    final seq = ++_searchSeq;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _answer = null;
      _lastQuery = query;
    });
    try {
      final raw = await widget.apiClient
          .search(query, category: _category, createdAfter: _range.createdAfter);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = raw.map((e) => SearchResult.fromJson(e as Map<String, dynamic>)).toList();
      });
    } on ApiException catch (e) {
      if (mounted && seq == _searchSeq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _searchSeq) setState(() => _loading = false);
    }
  }

  void _setFilter({String? category, _TimeRange? range, bool clearCategory = false}) {
    setState(() {
      if (clearCategory) _category = null;
      if (category != null) _category = category;
      if (range != null) _range = range;
    });
    // The old results no longer match the filter -- search again if we already had.
    if (_lastQuery != null) _search();
  }

  Future<void> _askAi() async {
    final query = _lastQuery;
    if (query == null || _answerLoading) return;
    final seq = _searchSeq;
    setState(() => _answerLoading = true);
    try {
      final data = await widget.apiClient
          .searchAnswer(query, category: _category, createdAfter: _range.createdAfter);
      // The user searched again (different query/filter) while waiting -> stale.
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _answer = data['answer'] as String? ?? 'The AI is unavailable right now, try again later.';
      });
    } on ApiException catch (e) {
      if (mounted && seq == _searchSeq) setState(() => _answer = e.message);
    } finally {
      if (mounted) setState(() => _answerLoading = false);
    }
  }

  void _replace(Item updated) {
    setState(() {
      _results = [
        for (final r in _results!) r.item.id == updated.id ? SearchResult(item: updated, score: r.score) : r
      ];
    });
  }

  void _remove(Item removed) {
    setState(() {
      _results = _results!.where((r) => r.item.id != removed.id).toList();
      // The [n] numbers in the answer point at list positions -- once an item
      // is removed the numbers shift and the answer points at the wrong items.
      _answer = null;
    });
  }

  Widget _filterBar() {
    final cats = _categories;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (cats != null)
            PopupMenuButton<String>(
              tooltip: 'Filter by category',
              onSelected: (c) =>
                  c == _allCategories ? _setFilter(clearCategory: true) : _setFilter(category: c),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _allCategories, child: Text('All categories')),
                for (final c in cats) PopupMenuItem(value: c, child: Text(c)),
              ],
              child: _FilterPill(label: _category ?? 'All categories', active: _category != null),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<_TimeRange>(
            tooltip: 'Filter by date saved',
            onSelected: (r) => _setFilter(range: r),
            itemBuilder: (_) => [for (final r in _TimeRange.values) PopupMenuItem(value: r, child: Text(r.label))],
            child: _FilterPill(label: _range.label, active: _range != _TimeRange.any),
          ),
          if (_hasFilter) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => _setFilter(clearCategory: true, range: _TimeRange.any),
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  /// The [1], [2] numbers in the answer point at positions in the result list
  /// below it: /search/answer uses the same retrieval (and filters), top 5, so
  /// the order is identical to the first 5 results of /search.
  Widget _answerCard() {
    final theme = Theme.of(context);
    Widget child;
    if (_answerLoading) {
      child = const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Summarising…'),
      ]);
    } else if (_answer != null) {
      child = Text(_answer!, style: theme.textTheme.bodyMedium);
    } else {
      child = Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _askAi,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Summarise with AI'),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  Widget _centered(List<Widget> children) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _centered([
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _search, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      ]);
    }
    final results = _results;
    if (results == null) {
      return _centered(const [
        Text(
          'Search in plain words, for example\n"spicy food recipes" or "workout videos".\n\n'
          'Narrow it down with the category or date filters above.',
          textAlign: TextAlign.center,
        ),
      ]);
    }
    if (results.isEmpty) {
      return _centered([
        Text(_hasFilter ? 'Nothing matches these filters.' : 'Nothing matches.'),
        if (_hasFilter) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _setFilter(clearCategory: true, range: _TimeRange.any),
            child: const Text('Search without filters'),
          ),
        ],
      ]);
    }
    return ListView.builder(
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _answerCard();
        final i = index - 1;
        final r = results[i];
        return ItemTile(
          key: ValueKey(r.item.id),
          apiClient: widget.apiClient,
          item: r.item,
          onChanged: _replace,
          onDeleted: _remove,
          leading: Text('[${i + 1}]', style: Theme.of(context).textTheme.labelMedium),
          trailingInfo: Text(r.score.toStringAsFixed(2), style: Theme.of(context).textTheme.labelSmall),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(hintText: 'Search your saved items…', border: InputBorder.none),
        ),
        actions: [IconButton(onPressed: _search, tooltip: 'Search', icon: const Icon(Icons.search))],
      ),
      body: Column(children: [
        _filterBar(),
        const Divider(height: 1),
        Expanded(child: _body()),
      ]),
    );
  }
}

/// A small "dropdown button" look for a filter. [active] = the filter is in
/// use, highlighted so the user notices the results are narrowed down.
class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  const _FilterPill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? scheme.secondaryContainer : null,
        border: Border.all(color: active ? scheme.secondary : scheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: active ? scheme.onSecondaryContainer : null)),
        const Icon(Icons.arrow_drop_down, size: 20),
      ]),
    );
  }
}
