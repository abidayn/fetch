import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../widgets/item_tile.dart';

/// Pilihan rentang waktu untuk filter `created_after`. Relatif ke hari ini,
/// karena "yang kusimpan minggu lalu" lebih alami daripada memilih tanggal.
enum _TimeRange {
  any('Kapan saja', null),
  week('7 hari terakhir', 7),
  month('30 hari terakhir', 30),
  year('1 tahun terakhir', 365);

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

  // null = belum pernah mencari (tampilkan petunjuk), [] = sudah mencari
  // tapi tidak ada yang cocok. Dua keadaan berbeda, pesan berbeda.
  List<SearchResult>? _results;
  String? _error;
  bool _loading = false;

  // Filter terstruktur hybrid search -- dikirim ke backend dan disaring di
  // SQL yang sama dengan pencarian vektor, bukan disaring dari hasil di app.
  String? _category;
  _TimeRange _range = _TimeRange.any;
  List<String>? _categories;

  // Jawaban AI diminta terpisah lewat tombol, bukan otomatis tiap pencarian:
  // tiap jawaban = satu panggilan Gemini (kuota free tier harian terbatas),
  // dan sering daftar hasilnya saja sudah cukup.
  String? _answer;
  bool _answerLoading = false;
  String? _lastQuery;

  // Nomor urut pencarian: hasil dari pencarian lama (mis. filter diganti
  // saat request masih jalan) dibuang, bukan menimpa hasil yang lebih baru.
  int _searchSeq = 0;

  // Nilai menu "semua kategori". Bukan null: PopupMenuButton menganggap
  // pilihan bernilai null sebagai "dibatalkan" dan tidak memanggil onSelected.
  static const _allCategories = '';

  bool get _hasFilter => _category != null || _range != _TimeRange.any;

  @override
  void initState() {
    super.initState();
    widget.apiClient.listCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {
      // Tanpa daftar kategori, filter kategori disembunyikan; cari tetap jalan.
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Dipanggil saat user menekan enter/tombol cari (atau mengganti filter),
  /// BUKAN tiap ketikan: setiap pencarian = satu panggilan embedding ke
  /// Gemini. Search-as-you-type akan menghabiskan kuota untuk potongan kata
  /// yang tidak bermakna ("res", "rese", "resep").
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
    // Hasil lama tidak lagi sesuai filter -- cari ulang kalau sudah pernah.
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
      // User sudah mencari ulang (query/filter lain) selagi menunggu -> basi.
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _answer = data['answer'] as String? ?? 'AI sedang tidak tersedia, coba lagi nanti.';
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
      // Nomor [n] di jawaban menunjuk urutan daftar -- setelah ada yang
      // hilang, nomornya bergeser dan jawaban jadi menunjuk item yang salah.
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
              tooltip: 'Filter kategori',
              onSelected: (c) =>
                  c == _allCategories ? _setFilter(clearCategory: true) : _setFilter(category: c),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _allCategories, child: Text('Semua kategori')),
                for (final c in cats) PopupMenuItem(value: c, child: Text(c)),
              ],
              child: _FilterPill(label: _category ?? 'Semua kategori', active: _category != null),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<_TimeRange>(
            tooltip: 'Filter waktu simpan',
            onSelected: (r) => _setFilter(range: r),
            itemBuilder: (_) => [for (final r in _TimeRange.values) PopupMenuItem(value: r, child: Text(r.label))],
            child: _FilterPill(label: _range.label, active: _range != _TimeRange.any),
          ),
          if (_hasFilter) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => _setFilter(clearCategory: true, range: _TimeRange.any),
              child: const Text('Hapus filter'),
            ),
          ],
        ],
      ),
    );
  }

  /// Nomor [1], [2] di jawaban menunjuk urutan di daftar hasil di bawahnya:
  /// /search/answer memakai retrieval (dan filter) yang sama, 5 teratas, jadi
  /// urutannya identik dengan 5 hasil pertama /search.
  Widget _answerCard() {
    final theme = Theme.of(context);
    Widget child;
    if (_answerLoading) {
      child = const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Merangkum…'),
      ]);
    } else if (_answer != null) {
      child = Text(_answer!, style: theme.textTheme.bodyMedium);
    } else {
      child = Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _askAi,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Rangkum dengan AI'),
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
        FilledButton.icon(onPressed: _search, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
      ]);
    }
    final results = _results;
    if (results == null) {
      return _centered(const [
        Text(
          'Cari pakai kalimat biasa, misalnya\n"resep masakan pedas" atau "video olahraga".\n\n'
          'Persempit dengan kategori atau waktu simpan di atas.',
          textAlign: TextAlign.center,
        ),
      ]);
    }
    if (results.isEmpty) {
      return _centered([
        Text(_hasFilter ? 'Tidak ada yang cocok dengan filter ini.' : 'Tidak ada yang cocok.'),
        if (_hasFilter) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _setFilter(clearCategory: true, range: _TimeRange.any),
            child: const Text('Cari tanpa filter'),
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
          decoration: const InputDecoration(hintText: 'Cari yang pernah disimpan…', border: InputBorder.none),
        ),
        actions: [IconButton(onPressed: _search, tooltip: 'Cari', icon: const Icon(Icons.search))],
      ),
      body: Column(children: [
        _filterBar(),
        const Divider(height: 1),
        Expanded(child: _body()),
      ]),
    );
  }
}

/// Tampilan "tombol dropdown" kecil untuk filter. [active] = filter sedang
/// dipakai, ditandai warna supaya user sadar hasil sedang dipersempit.
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
