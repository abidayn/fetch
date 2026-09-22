import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import 'token_storage.dart';

/// Dilempar kalau backend menjawab dengan status di luar 2xx.
/// [statusCode] dipakai UI buat bedain kasus (401 vs 404 vs lainnya).
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

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

  /// Emulator Android punya jaringan virtual sendiri -- "localhost" di
  /// emulator menunjuk ke emulator itu sendiri, BUKAN ke mesin host tempat
  /// backend jalan. 10.0.2.2 adalah alias khusus yang disediakan Android
  /// emulator untuk menunjuk balik ke localhost host. Ini cuma berlaku
  /// untuk emulator resmi Android Studio -- device fisik butuh IP LAN asli.
  static String get _baseUrl {
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
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
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _handle(res) as Map<String, dynamic>;
  }

  /// Login sukses -> token langsung disimpan di sini, di satu tempat.
  /// Pemanggil (LoginScreen) tidak perlu tahu-menahu soal token storage.
  Future<void> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _handle(res) as Map<String, dynamic>;
    await _tokenStorage.save(data['access_token'] as String);
  }

  Future<void> logout() => _tokenStorage.clear();

  Future<bool> hasToken() async => (await _tokenStorage.read()) != null;

  Future<List<dynamic>> listItems() async {
    final res = await http.get(Uri.parse('$_baseUrl/items'), headers: await _headers());
    return _handle(res) as List<dynamic>;
  }

  /// Cukup kirim url -- title/summary/category diisi otomatis oleh backend.
  Future<Map<String, dynamic>> createItem(String url) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/items'),
      headers: await _headers(),
      body: jsonEncode({'url': url}),
    );
    return _handle(res) as Map<String, dynamic>;
  }

  /// Pencarian semantik. Hasil sudah terurut dari yang paling mirip dan
  /// sudah disaring relevansinya di backend -- list kosong itu jawaban sah
  /// ("tidak ada yang cocok"), bukan error.
  Future<List<dynamic>> search(String query, {int limit = 10}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/search'),
      headers: await _headers(),
      body: jsonEncode({'query': query, 'limit': limit}),
    );
    return _handle(res) as List<dynamic>;
  }

  /// RAG lengkap: backend mencari item relevan lalu Gemini merangkai jawaban.
  /// `answer` bisa null (Gemini gagal / kuota habis) -- `sources` tetap ada.
  Future<Map<String, dynamic>> searchAnswer(String query) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/search/answer'),
      headers: await _headers(),
      body: jsonEncode({'query': query}),
    );
    return _handle(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getItem(String id) async {
    final res = await http.get(Uri.parse('$_baseUrl/items/$id'), headers: await _headers());
    return _handle(res) as Map<String, dynamic>;
  }

  Future<void> deleteItem(String id) async {
    final res = await http.delete(Uri.parse('$_baseUrl/items/$id'), headers: await _headers());
    _handle(res);
  }
}
