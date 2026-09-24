import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../widgets/item_tile.dart';
import '../widgets/save_result_sheet.dart';
import 'login_screen.dart';
import 'search_screen.dart';

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
  // State eksplisit, bukan FutureBuilder: edit & hapus mengubah list di
  // tempat (tanpa muat ulang semua), dan gagal-refresh saat data lama masih
  // ada cukup jadi snackbar -- bukan mengganti seluruh layar dengan error.
  List<Item>? _items;
  ApiException? _error;
  bool _loading = false;

  // null = "Semua". Browse per kategori disaring di sisi app: semua item
  // user sudah dimuat untuk daftar ini, jadi tidak perlu request lagi.
  String? _category;

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
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool fromPoll = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (_items == null) _error = null;
    });
    try {
      final raw = await widget.apiClient.listItems();
      if (!mounted) return;
      final items = raw.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
      setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_items == null || e.isUnauthorized) {
        setState(() => _error = e);
      } else if (!fromPoll) {
        // Data lama masih berguna -- cukup kabari, jangan kosongkan layar.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui: ${e.message}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        // Di finally: poll yang gagal (jaringan sesaat) tetap dijadwalkan ulang.
        _schedulePollIfPending();
      }
    }
  }

  void _schedulePollIfPending() {
    _pollTimer?.cancel();
    final pending = _items?.any((it) => !it.processed) ?? false;
    if (!pending || _polls >= _maxPolls || !mounted) return;
    _pollTimer = Timer(_pollInterval, () {
      if (!mounted) return;
      _polls++;
      _load(fromPoll: true);
    });
  }

  Future<void> refresh() {
    _polls = 0;
    return _load();
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

  /// Form manual "tempel link" -- jalur cadangan kalau app asal tidak punya
  /// tombol share ke Fetch, dan berguna buat testing.
  Future<void> _addManually() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan link'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://...'),
          keyboardType: TextInputType.url,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _save(url);
  }

  Future<void> _save(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Menyimpan…'), duration: Duration(seconds: 30)));
    try {
      final item = Item.fromJson(await widget.apiClient.createItem(url));
      messenger.hideCurrentSnackBar();
      refresh();
      if (!mounted) return;
      await showSaveResultSheet(context, widget.apiClient, item);
      refresh();
    } on ApiException catch (e) {
      messenger.hideCurrentSnackBar();
      // POST tidak diulang otomatis (bisa dobel), jadi user yang memutuskan.
      messenger.showSnackBar(SnackBar(
        content: Text('Gagal menyimpan: ${e.message}'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Coba lagi', onPressed: () => _save(url)),
      ));
    }
  }

  void _replace(Item updated) {
    setState(() {
      _items = [for (final it in _items!) it.id == updated.id ? updated : it];
    });
  }

  void _remove(Item removed) {
    setState(() {
      _items = _items!.where((it) => it.id != removed.id).toList();
    });
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SearchScreen(apiClient: widget.apiClient)))
        // Item bisa diedit/dihapus dari layar cari -- samakan saat kembali.
        .then((_) => refresh());
  }

  /// Chip kategori yang benar-benar dipakai user, urut dari yang paling
  /// banyak isinya. Kategori kosong tidak ditampilkan -- chip yang selalu
  /// menghasilkan layar kosong cuma bikin bingung.
  Widget _categoryChips(List<Item> items) {
    final counts = <String, int>{};
    for (final it in items) {
      final c = it.category;
      if (c != null) counts[c] = (counts[c] ?? 0) + 1;
    }
    final cats = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('Semua (${items.length})'),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
          ),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$c (${counts[c]})'),
                selected: _category == c,
                onSelected: (sel) => setState(() => _category = sel ? c : null),
              ),
            ),
        ],
      ),
    );
  }

  /// Pesan di tengah layar yang tetap bisa ditarik untuk refresh.
  Widget _message({required IconData icon, required String title, String? detail, Widget? action}) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(detail, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: 16), Center(child: action)],
      ],
    );
  }

  Widget _body() {
    final items = _items;
    final error = _error;

    if (error != null && error.isUnauthorized) {
      return _message(
        icon: Icons.lock_outline,
        title: 'Sesi sudah berakhir',
        detail: 'Masuk lagi untuk melihat item tersimpan.',
        action: FilledButton(onPressed: _logout, child: const Text('Masuk lagi')),
      );
    }
    if (items == null) {
      if (error != null) {
        return _message(
          icon: Icons.cloud_off,
          title: 'Gagal memuat',
          detail: error.message,
          action: FilledButton.icon(
            onPressed: _loading ? null : refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return _message(
        icon: Icons.bookmark_add_outlined,
        title: 'Belum ada yang disimpan',
        detail: 'Dari YouTube, TikTok, atau browser, tekan Share lalu pilih Fetch. '
            'Atau tekan + untuk menempel link.',
      );
    }

    // Kategori yang dipilih bisa hilang (item terakhirnya dihapus/diedit).
    final category = items.any((it) => it.category == _category) ? _category : null;
    final visible = category == null ? items : items.where((it) => it.category == category).toList();

    return Column(children: [
      _categoryChips(items),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88), // ruang untuk FAB
          itemCount: visible.length,
          itemBuilder: (context, i) => ItemTile(
            key: ValueKey(visible[i].id),
            apiClient: widget.apiClient,
            item: visible[i],
            onChanged: _replace,
            onDeleted: _remove,
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fetch'),
        bottom: _loading && _items != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
        actions: [
          IconButton(onPressed: _openSearch, tooltip: 'Cari', icon: const Icon(Icons.search)),
          IconButton(onPressed: _logout, tooltip: 'Keluar', icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(onRefresh: refresh, child: _body()),
      floatingActionButton: FloatingActionButton(
        onPressed: _addManually,
        tooltip: 'Simpan link',
        child: const Icon(Icons.add),
      ),
    );
  }
}
