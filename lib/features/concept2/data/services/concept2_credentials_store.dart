import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/concept2_models.dart';

final class Concept2CredentialsStore {
  Concept2CredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'concept2_logbook_access_token';

  final FlutterSecureStorage _storage;

  Future<Concept2Credentials?> read() async {
    final token = (await _storage.read(key: _tokenKey))?.trim();
    return token == null || token.isEmpty ? null : Concept2Credentials(token);
  }

  Future<void> save(Concept2Credentials credentials) =>
      _storage.write(key: _tokenKey, value: credentials.accessToken.trim());

  Future<void> clear() => _storage.delete(key: _tokenKey);
}
