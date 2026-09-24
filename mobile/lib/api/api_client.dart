import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:http/http.dart' as http;

import 'token_storage.dart';

/// Dilempar kalau backend menjawab dengan status di luar 2xx.
/// [statusCode] dipakai UI buat bedain kasus (401 vs 404 vs lainnya).
/// [statusCode] 0 = request tidak pernah sampai / tidak dijawab (offline,
/// timeout) -- dibedakan supaya UI tidak perlu menangkap SocketException dll.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Satu pintu masuk untuk semua HTTP ke backend Fetch.
///
/// Kenapa disentralisasi di satu class, bukan http.get/post tersebar di
/// tiap screen: base URL dan header Authorization jadi satu tempat. Kalau
/// nanti pindah dari localhost ke server production (Fase 5), cuma
/// [_baseUrl] yang berubah -- tidak ada screen yang perlu disentuh.
class ApiClient {
  final TokenStorage _tokenStorage;
  ApiClient(this._tokenStorage);

  /// Diisi saat build production: --dart-define=API_BASE_URL=https://...
  /// Kalau tidak diisi (flutter run biasa saat dev), jatuh ke backend lokal.
  static const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Emulator Android punya jaringan virtual sendiri -- "localhost" di
  /// emulator menunjuk ke emulator itu sendiri, BUKAN ke mesin host tempat
  /// backend jalan. 10.0.2.2 adalah alias khusus yang disediakan Android
  /// emulator untuk menunjuk balik ke localhost host. Ini cuma berlaku
  /// untuk emulator resmi Android Studio -- device fisik butuh IP LAN asli.
  static String get _baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  // Batas tunggu satu request. Lebih longgar dari biasanya karena server
  // Railway bisa "tidur" (Serverless) dan butuh belasan detik untuk bangun.
  static const _timeout = Duration(seconds: 30);

  // Status yang berarti "server/gateway sedang tidak siap", bukan "request
  // salah" -- 502 muncul di request pertama saat Railway baru bangun (§5.4).
  static const _transientStatuses = {502, 503, 504};

  /// Kirim request dengan timeout, dan ulangi SEKALI kalau gagalnya sementara
  /// (jaringan putus, timeout, 502/503/504).
  ///
  /// [retry] cuma boleh true untuk request yang aman diulang (idempotent):
  /// GET, PATCH, DELETE, login, dan pencarian. POST /items TIDAK -- kalau
  /// request pertama sebenarnya sudah sampai tapi balasannya hilang,
  /// mengulang = link tersimpan dua kali. Untuk itu user menekan "Coba lagi".
  Future<http.Response> _send(Future<http.Response> Function() request, {bool retry = true}) async {
    for (var attempt = 1;; attempt++) {
      final canRetry = retry && attempt < 2;
      try {
        final res = await request().timeout(_timeout);
        if (canRetry && _transientStatuses.contains(res.statusCode)) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return res;
      } on SocketException {
        if (canRetry) continue;
        throw ApiException(0, 'Tidak bisa terhubung ke server. Cek koneksi internet.');
      } on http.ClientException {
        if (canRetry) continue;
        throw ApiException(0, 'Tidak bisa terhubung ke server. Cek koneksi internet.');
      } on TimeoutException {
        if (canRetry) continue;
        throw ApiException(0, 'Server terlalu lama menjawab. Coba lagi.');
      }
    }
  }

  Future<Map<String, String>> _headers({bool withAuth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (withAuth) {
      final token = await _tokenStorage.read();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Menerjemahkan response HTTP jadi data Dart, atau melempar ApiException.
  /// Satu tempat ini yang dipakai semua method di bawah -- jangan duplikasi
  /// pengecekan status code di tiap pemanggil.
  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null; // contoh: 204 No Content dari DELETE
      return jsonDecode(res.body);
    }

    String message = 'Terjadi kesalahan (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      final detail = body['detail'];
      // FastAPI kirim `detail` sebagai string (error kita sendiri) ATAU
      // sebagai list of object (dari validasi Pydantic, kode 422) --
      // dua bentuk berbeda, keduanya perlu ditangani.
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        message = detail.first['msg'] ?? message;
      }
    } catch (_) {
      // Body bukan JSON valid -- pertahankan pesan default di atas.
    }
    throw ApiException(res.statusCode, message);
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    // Tidak diulang: kalau percobaan pertama ternyata sudah membuat akun,
    // percobaan kedua dijawab "email sudah terdaftar" -- membingungkan.
    final res = await _send(retry: false, () async => http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({'email': email, 'password': password}),
    ));
    return _handle(res) as Map<String, dynamic>;
  }

  /// Login sukses -> token langsung disimpan di sini, di satu tempat.
  /// Pemanggil (LoginScreen) tidak perlu tahu-menahu soal token storage.
  Future<void> login(String email, String password) async {
    final res = await _send(() async => http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({'email': email, 'password': password}),
    ));
    final data = _handle(res) as Map<String, dynamic>;
    await _tokenStorage.save(data['access_token'] as String);
  }

  Future<void> logout() => _tokenStorage.clear();

  Future<bool> hasToken() async => (await _tokenStorage.read()) != null;

  Future<List<dynamic>> listItems() async {
    final headers = await _headers();
    final res = await _send(() => http.get(Uri.parse('$_baseUrl/items'), headers: headers));
    return _handle(res) as List<dynamic>;
  }

  List<String>? _categories;

  /// Daftar kategori tetap dari backend (classifier.py). Di-cache: daftarnya
  /// cuma berubah kalau backend di-deploy ulang dengan kategori baru.
  Future<List<String>> listCategories() async {
    final cached = _categories;
    if (cached != null) return cached;
    final headers = await _headers();
    final res = await _send(() => http.get(Uri.parse('$_baseUrl/items/categories'), headers: headers));
    return _categories = (_handle(res) as List<dynamic>).cast<String>();
  }

  /// Cukup kirim url -- title/summary/category diisi otomatis oleh backend.
  Future<Map<String, dynamic>> createItem(String url) async {
    final res = await _send(retry: false, () async => http.post(
      Uri.parse('$_baseUrl/items'),
      headers: await _headers(),
      body: jsonEncode({'url': url}),
    ));
    return _handle(res) as Map<String, dynamic>;
  }

  /// Pencarian semantik. Hasil sudah terurut dari yang paling mirip dan
  /// sudah disaring relevansinya di backend -- list kosong itu jawaban sah
  /// ("tidak ada yang cocok"), bukan error.
  ///
  /// [category] / [createdAfter] = bagian terstruktur hybrid search: disaring
  /// di SQL yang sama dengan pencarian vektor (backend/routers/search.py).
  Future<List<dynamic>> search(String query,
      {int limit = 10, String? category, DateTime? createdAfter}) async {
    final res = await _send(() async => http.post(
      Uri.parse('$_baseUrl/search'),
      headers: await _headers(),
      body: jsonEncode({'query': query, 'limit': limit, ..._filters(category, createdAfter)}),
    ));
    return _handle(res) as List<dynamic>;
  }

  /// RAG lengkap: backend mencari item relevan lalu Gemini merangkai jawaban.
  /// `answer` bisa null (Gemini gagal / kuota habis) -- `sources` tetap ada.
  Future<Map<String, dynamic>> searchAnswer(String query,
      {String? category, DateTime? createdAfter}) async {
    final res = await _send(() async => http.post(
      Uri.parse('$_baseUrl/search/answer'),
      headers: await _headers(),
      body: jsonEncode({'query': query, ..._filters(category, createdAfter)}),
    ));
    return _handle(res) as Map<String, dynamic>;
  }

  Map<String, dynamic> _filters(String? category, DateTime? createdAfter) => {
        'category': ?category,
        if (createdAfter != null) 'created_after': createdAfter.toUtc().toIso8601String(),
      };

  Future<Map<String, dynamic>> getItem(String id) async {
    final headers = await _headers();
    final res = await _send(() => http.get(Uri.parse('$_baseUrl/items/$id'), headers: headers));
    return _handle(res) as Map<String, dynamic>;
  }

  /// Cuma field yang dikirim yang diubah. Backend menolak (409) selama item
  /// masih diproses AI, karena hasil AI akan menimpa editan.
  Future<Map<String, dynamic>> updateItem(String id,
      {String? title, String? summary, String? category}) async {
    final headers = await _headers();
    final res = await _send(() => http.patch(
          Uri.parse('$_baseUrl/items/$id'),
          headers: headers,
          body: jsonEncode({
            'title': ?title,
            'summary': ?summary,
            'category': ?category,
          }),
        ));
    return _handle(res) as Map<String, dynamic>;
  }

  /// Diulang otomatis kalau gagal sementara: DELETE kedua atas item yang
  /// ternyata sudah terhapus menjawab 404 -- itu juga dianggap berhasil.
  Future<void> deleteItem(String id) async {
    final headers = await _headers();
    final res = await _send(() => http.delete(Uri.parse('$_baseUrl/items/$id'), headers: headers));
    if (res.statusCode == 404) return;
    _handle(res);
  }
}
