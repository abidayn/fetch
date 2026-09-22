import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper tipis di atas flutter_secure_storage, khusus JWT.
///
/// Kenapa secure storage, bukan SharedPreferences: SharedPreferences di
/// Android tersimpan sebagai XML polos yang bisa dibaca di perangkat rooted
/// atau lewat adb backup. flutter_secure_storage memakai Keystore (Android)
/// / Keychain (iOS) -- storage terenkripsi milik OS, dirancang khusus untuk
/// data sensitif seperti token.
class TokenStorage {
  static const _key = 'access_token';
  final _storage = const FlutterSecureStorage();

  Future<void> save(String token) => _storage.write(key: _key, value: token);

  Future<String?> read() => _storage.read(key: _key);

  Future<void> clear() => _storage.delete(key: _key);
}
