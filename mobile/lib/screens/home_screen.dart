import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../util/open_link.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import '../widgets/save_result_sheet.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;
  final GlobalKey<HomeScreenState>? homeKey;
  const HomeScreen({super.key, required this.apiClient, this.homeKey});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

/// State di-expose (bukan diawali `_`) supaya main.dart bisa manggil
/// `refresh()` dari GlobalKey ketika ada link baru masuk lewat share-sheet,
/// tanpa perlu state management library buat satu kasus ini.
class HomeScreenState extends State<HomeScreen> {
  late Future<List<Item>> _future;

  // Pengayaan AI jalan di background 5-10 detik SETELAH item disimpan, jadi
  // item baru awalnya tampil "memproses". Selama masih ada item yang belum
  // diproses, list dimuat ulang tiap 4 detik -- dibatasi 10x (~40 detik)
  // supaya tidak polling selamanya kalau server bermasalah.
  static const _pollInterval = Duration(seconds: 4);
  static const _maxPolls = 10;
  Timer? _pollTimer;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<List<Item>> _load() async {
    final raw = await widget.apiClient.listItems();
    final items = raw.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
    _schedulePollIfPending(items);
    return items;
  }

  void _schedulePollIfPending(List<Item> items) {
    _pollTimer?.cancel();
    final pending = items.any((it) => !it.processed);
    if (!pending || _polls >= _maxPolls || !mounted) return;
    _pollTimer = Timer(_pollInterval, () {
      if (!mounted) return;
      _polls++;
      setState(() {
        _future = _load();
      });
    });
  }

  void refresh() {
    // Bug nyata yang ketemu saat uji share-sheet: `setState(() => _future =
    // _load())` -- closure arrow-style itu me-return NILAI hasil assignment,
    // yaitu Future<List<Item>> dari _load(). Flutter melempar assertion
    // error kalau callback setState() mengembalikan Future (karena setState
    // harus sinkron). Efeknya sebelumnya: assignment tetap kejadian (item
    // sudah tersimpan di backend), tapi rebuild-nya gagal ditengah jalan dan
    // errornya salah kaprah ketangkap sebagai "gagal simpan link" di
    // main.dart. Fix: pakai block body {} supaya closure return void.
    _polls = 0;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _logout() async {
    await widget.apiClient.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => LoginScreen(apiClient: widget.apiClient, homeKey: widget.homeKey)),
      (route) => false,
    );
  }

  /// Form manual "tempel link" -- pengganti sementara share-sheet, dan tetap
  /// berguna sebagai jalur cadangan buat testing tanpa harus share dari app
  /// lain tiap kali.
  Future<void> _addManually() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan link'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://...'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final item = Item.fromJson(await widget.apiClient.createItem(url));
      refresh();
      if (!mounted) return;
      await showSaveResultSheet(context, widget.apiClient, item);
      refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _subtitle(Item item) {
    if (!item.processed) {
      return const Text('Memproses…', style: TextStyle(fontStyle: FontStyle.italic));
    }
    final meta = [item.category, item.platform].whereType<String>().join(' · ');
    if (item.summary == null) {
      // Sudah diproses tapi tidak ada isi yang bisa dibaca (mis. Instagram
      // tanpa login) -- tampilkan apa adanya, bukan "memproses" selamanya.
      return Text(meta.isEmpty ? item.url : meta, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text('$meta\n${item.summary}', maxLines: 2, overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fetch'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SearchScreen(apiClient: widget.apiClient))),
            icon: const Icon(Icons.search),
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refresh(),
        child: FutureBuilder<List<Item>>(
          future: _future,
          builder: (context, snapshot) {
            // Spinner cuma untuk muat pertama. Saat polling/refresh, FutureBuilder
            // masih menyimpan data sebelumnya -- tampilkan itu supaya tidak berkedip.
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError && !snapshot.hasData) {
              return Center(child: Text('Gagal memuat: ${snapshot.error}'));
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return LayoutBuilder(
                builder: (context, _) => ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('Belum ada yang disimpan.')),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return ListTile(
                  title: Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: _subtitle(item),
                  isThreeLine: item.summary != null,
                  onTap: () => openLink(context, item.url),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addManually, child: const Icon(Icons.add)),
    );
  }
}
