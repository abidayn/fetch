import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'api/api_client.dart';
import 'api/token_storage.dart';
import 'models/item.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/save_result_sheet.dart';

void main() {
  runApp(FetchApp());
}

class FetchApp extends StatefulWidget {
  FetchApp({super.key});

  final apiClient = ApiClient(TokenStorage());

  @override
  State<FetchApp> createState() => _FetchAppState();
}

class _FetchAppState extends State<FetchApp> {
  StreamSubscription? _shareSub;

  // Key ke HomeScreen supaya bisa panggil refresh() dari sini kalau link
  // baru masuk sementara HomeScreen sedang ditampilkan. Tanpa ini butuh
  // state management library cuma buat komunikasi 1 arah yang jarang terjadi.
  final _homeKey = GlobalKey<HomeScreenState>();

  // Share datang dari luar pohon widget (callback plugin), jadi tidak ada
  // BuildContext di tangan. Key ini memberi akses ke Navigator milik
  // MaterialApp untuk menampilkan sheet "Saved" dari sini.
  final _navigatorKey = GlobalKey<NavigatorState>();

  // Alasan yang sama: snackbar "gagal simpan" dari luar pohon widget.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _listenForSharedLinks();
  }

  void _listenForSharedLinks() {
    // "Warm": app sedang kebuka (foreground/background) waktu user share.
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
      onError: (err) => debugPrint('Share stream error: $err'),
    );

    // "Cold start": app belum jalan sama sekali, dibuka LEWAT aksi share.
    // Ini kenapa harus dicek terpisah dari stream di atas -- stream cuma
    // menangkap share yang terjadi SETELAH app hidup dan listener terpasang;
    // share yang justru menyalakan app pertama kali akan terlewat kalau
    // cuma mengandalkan stream.
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedFiles);
  }

  void _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final url = files.first.path;

    // reset() wajib dipanggil -- tanpa ini, share yang sama akan terbaca
    // ULANG oleh getInitialMedia() setiap kali app dibuka lagi, bukan cuma
    // sekali waktu itu terjadi.
    ReceiveSharingIntent.instance.reset();

    if (!await widget.apiClient.hasToken()) {
      // Belum login -- tidak ada tempat aman untuk simpan link ini. MVP
      // sengaja tidak antre link untuk disimpan nanti; user share ulang
      // setelah login. Tapi user harus TAHU link-nya tidak tersimpan.
      await _showMessage('Masuk dulu, lalu share link-nya lagi.');
      return;
    }
    await _saveShared(url);
  }

  Future<void> _saveShared(String url) async {
    try {
      final item = Item.fromJson(await widget.apiClient.createItem(url));
      _homeKey.currentState?.refresh();
      await _showSavedSheet(item);
    } on ApiException catch (e) {
      // Tanpa ini, share yang gagal (server tidur, offline) hilang diam-diam
      // dan user mengira link-nya sudah tersimpan.
      await _showMessage('Gagal menyimpan link: ${e.message}',
          action: SnackBarAction(label: 'Coba lagi', onPressed: () => _saveShared(url)));
    }
  }

  Future<void> _showMessage(String text, {SnackBarAction? action}) async {
    await _waitForApp();
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(text), action: action, duration: const Duration(seconds: 8)),
    );
  }

  /// Cold start: share bisa diproses sebelum MaterialApp selesai membangun
  /// Navigator-nya. Tunggu sebentar (maks ~5 detik) sampai siap.
  Future<void> _waitForApp() async {
    for (var i = 0; i < 25 && _navigatorKey.currentContext == null; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _showSavedSheet(Item item) async {
    await _waitForApp();
    final ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showSaveResultSheet(ctx, widget.apiClient, item);
    _homeKey.currentState?.refresh(); // pastikan hasil akhir tampil di daftar
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Fetch',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      // FutureBuilder dipakai di root, bukan cuma langsung tampilkan
      // LoginScreen -- supaya kalau token TERSIMPAN dari sesi sebelumnya,
      // user tidak perlu login ulang tiap buka app.
      home: FutureBuilder<bool>(
        future: widget.apiClient.hasToken(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data!
              ? HomeScreen(key: _homeKey, apiClient: widget.apiClient, homeKey: _homeKey)
              : LoginScreen(apiClient: widget.apiClient, homeKey: _homeKey);
        },
      ),
    );
  }
}
