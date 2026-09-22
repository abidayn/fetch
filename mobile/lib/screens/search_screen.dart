import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../util/open_link.dart';

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

  // Jawaban AI diminta terpisah lewat tombol, bukan otomatis tiap pencarian:
  // tiap jawaban = satu panggilan Gemini (kuota free tier harian terbatas),
  // dan sering daftar hasilnya saja sudah cukup.
  String? _answer;
  bool _answerLoading = false;
  String? _lastQuery;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Dipanggil saat user menekan enter/tombol cari, BUKAN tiap ketikan:
  /// setiap pencarian = satu panggilan embedding ke Gemini (~0.5 detik +
  /// kuota free tier). Search-as-you-type akan menghabiskan kuota untuk
  /// potongan kata yang tidak bermakna ("res", "rese", "resep").
  Future<void> _search() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _answer = null;
      _lastQuery = query;
    });
    try {
      final raw = await widget.apiClient.search(query);
      setState(() {
        _results = raw.map((e) => SearchResult.fromJson(e as Map<String, dynamic>)).toList();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Tidak bisa terhubung ke server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _askAi() async {
    final query = _lastQuery;
    if (query == null || _answerLoading) return;
    setState(() => _answerLoading = true);
    try {
      final data = await widget.apiClient.searchAnswer(query);
      // User sudah mencari hal lain selagi menunggu -> jawaban ini basi.
      if (!mounted || query != _lastQuery) return;
      setState(() {
        _answer = data['answer'] as String? ?? 'AI sedang tidak tersedia, coba lagi nanti.';
      });
    } on ApiException catch (e) {
      setState(() => _answer = e.message);
    } catch (e) {
      setState(() => _answer = 'Tidak bisa terhubung ke server.');
    } finally {
      if (mounted) setState(() => _answerLoading = false);
    }
  }

  /// Nomor [1], [2] di jawaban menunjuk urutan di daftar hasil di bawahnya:
  /// /search/answer memakai retrieval yang sama (5 teratas), jadi urutannya
  /// identik dengan 5 hasil pertama /search.
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

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 8),
          TextButton(onPressed: _search, child: const Text('Coba lagi')),
        ]),
      );
    }
    final results = _results;
    if (results == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Cari pakai kalimat biasa, misalnya\n"resep masakan pedas" atau "video olahraga".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (results.isEmpty) return const Center(child: Text('Tidak ada yang cocok.'));
    return ListView.builder(
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _answerCard();
        final i = index - 1;
        final r = results[i];
        final meta = [r.item.category, r.item.platform].whereType<String>().join(' · ');
        return ListTile(
          leading: Text('[${i + 1}]', style: Theme.of(context).textTheme.labelMedium),
          minLeadingWidth: 24,
          title: Text(r.item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [meta, if (r.item.summary != null) r.item.summary!].where((s) => s.isNotEmpty).join('\n'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: r.item.summary != null,
          onTap: () => openLink(context, r.item.url),
          trailing: Text(r.score.toStringAsFixed(2), style: Theme.of(context).textTheme.labelMedium),
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
        actions: [IconButton(onPressed: _search, icon: const Icon(Icons.search))],
      ),
      body: _body(),
    );
  }
}
