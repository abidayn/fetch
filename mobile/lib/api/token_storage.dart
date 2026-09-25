import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A thin wrapper over flutter_secure_storage, for the JWT only.
///
/// Why secure storage rather than SharedPreferences: on Android,
/// SharedPreferences is stored as plain XML that can be read on a rooted
/// device or via adb backup. flutter_secure_storage uses the Keystore
/// (Android) / Keychain (iOS) -- the OS's encrypted storage, built
/// specifically for sensitive data like tokens.
class TokenStorage {
  static const _key = 'access_token';
  final _storage = const FlutterSecureStorage();

  Future<void> save(String token) => _storage.write(key: _key, value: token);

  Future<String?> read() => _storage.read(key: _key);

  Future<void> clear() => _storage.delete(key: _key);
}
