import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:http/http.dart' as http;

import 'token_storage.dart';

/// Thrown when the backend answers with a status outside 2xx.
/// [statusCode] lets the UI tell cases apart (401 vs 404 vs others).
/// [statusCode] 0 = the request never arrived / got no answer (offline,
/// timeout) -- kept distinct so the UI doesn't have to catch SocketException etc.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The single entry point for all HTTP to the Fetch backend.
///
/// Why centralised in one class, rather than http.get/post scattered across
/// screens: the base URL and the Authorization header live in one place.
/// Moving from localhost to the production server only changes [_baseUrl]
/// -- no screen has to be touched.
class ApiClient {
  final TokenStorage _tokenStorage;
  ApiClient(this._tokenStorage);

  /// Set for production builds: --dart-define=API_BASE_URL=https://...
  /// When not set (a plain `flutter run` during dev), falls back to the local backend.
  static const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// The Android emulator has its own virtual network -- "localhost" in the
  /// emulator points at the emulator itself, NOT at the host machine running
  /// the backend. 10.0.2.2 is a special alias the Android emulator provides
  /// to point back at the host's localhost. It only applies to the official
  /// Android Studio emulator -- a physical device needs a real LAN IP.
  static String get _baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  // How long to wait for one request. Looser than usual because the Railway
  // server can "sleep" (Serverless) and takes a dozen-plus seconds to wake up.
  static const _timeout = Duration(seconds: 30);

  // Statuses that mean "the server/gateway isn't ready", not "the request is
  // wrong" -- a 502 shows up on the first request while Railway is waking up.
  static const _transientStatuses = {502, 503, 504};

  /// Send a request with a timeout, and retry ONCE if the failure is transient
  /// (network drop, timeout, 502/503/504).
  ///
  /// [retry] may only be true for requests that are safe to repeat
  /// (idempotent): GET, PATCH, DELETE, login, and search. POST /items is NOT
  /// -- if the first request actually arrived but its reply was lost,
  /// repeating it = the link is saved twice. For that, the user taps "Try again".
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
        throw ApiException(0, "Can't reach the server. Check your internet connection.");
      } on http.ClientException {
        if (canRetry) continue;
        throw ApiException(0, "Can't reach the server. Check your internet connection.");
      } on TimeoutException {
        if (canRetry) continue;
        throw ApiException(0, 'The server took too long to respond. Try again.');
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

  /// Turns an HTTP response into Dart data, or throws ApiException.
  /// Every method below goes through this one place -- don't duplicate
  /// status-code checks in each caller.
  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null; // e.g. 204 No Content from DELETE
      return jsonDecode(res.body);
    }

    String message = 'Something went wrong (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      final detail = body['detail'];
      // FastAPI sends `detail` as a string (our own errors) OR as a list of
      // objects (from Pydantic validation, status 422) -- two different
      // shapes, both need handling.
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        message = detail.first['msg'] ?? message;
      }
    } catch (_) {
      // Body isn't valid JSON -- keep the default message above.
    }
    throw ApiException(res.statusCode, message);
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    // Not retried: if the first attempt actually created the account, the
    // second one gets "email already registered" -- confusing.
    final res = await _send(retry: false, () async => http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({'email': email, 'password': password}),
    ));
    return _handle(res) as Map<String, dynamic>;
  }

  /// Successful login -> the token is saved right here, in one place.
  /// The caller (LoginScreen) doesn't need to know anything about token storage.
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

  /// The fixed category list from the backend (classifier.py). Cached: the
  /// list only changes when the backend is redeployed with new categories.
  Future<List<String>> listCategories() async {
    final cached = _categories;
    if (cached != null) return cached;
    final headers = await _headers();
    final res = await _send(() => http.get(Uri.parse('$_baseUrl/items/categories'), headers: headers));
    return _categories = (_handle(res) as List<dynamic>).cast<String>();
  }

  /// Just send the url -- title/summary/category are filled in by the backend.
  Future<Map<String, dynamic>> createItem(String url) async {
    final res = await _send(retry: false, () async => http.post(
      Uri.parse('$_baseUrl/items'),
      headers: await _headers(),
      body: jsonEncode({'url': url}),
    ));
    return _handle(res) as Map<String, dynamic>;
  }

  /// Semantic search. Results are already sorted most-similar first and
  /// relevance-filtered by the backend -- an empty list is a valid answer
  /// ("nothing matches"), not an error.
  ///
  /// [category] / [createdAfter] = the structured part of hybrid search:
  /// filtered in the same SQL as the vector search (backend/routers/search.py).
  Future<List<dynamic>> search(String query,
      {int limit = 10, String? category, DateTime? createdAfter}) async {
    final res = await _send(() async => http.post(
      Uri.parse('$_baseUrl/search'),
      headers: await _headers(),
      body: jsonEncode({'query': query, 'limit': limit, ..._filters(category, createdAfter)}),
    ));
    return _handle(res) as List<dynamic>;
  }

  /// Full RAG: the backend finds relevant items, then Gemini writes an answer.
  /// `answer` can be null (Gemini failed / quota used up) -- `sources` is still there.
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

  /// Only the fields that are sent get changed. The backend rejects it (409)
  /// while the item is still being processed by the AI, since the AI output
  /// would overwrite the edit.
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

  /// Retried automatically on transient failures: a second DELETE of an item
  /// that turns out to be already deleted gets a 404 -- also treated as success.
  Future<void> deleteItem(String id) async {
    final headers = await _headers();
    final res = await _send(() => http.delete(Uri.parse('$_baseUrl/items/$id'), headers: headers));
    if (res.statusCode == 404) return;
    _handle(res);
  }
}
