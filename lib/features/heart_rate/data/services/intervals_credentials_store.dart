import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/intervals_models.dart';

final class IntervalsCredentialsStore {
  IntervalsCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _athleteIdKey = 'intervals_icu_athlete_id';
  static const _apiKeyKey = 'intervals_icu_api_key';

  final FlutterSecureStorage _storage;

  Future<IntervalsCredentials?> read() async {
    final values = await Future.wait([
      _storage.read(key: _athleteIdKey),
      _storage.read(key: _apiKeyKey),
    ]);
    final athleteId = values[0]?.trim();
    final apiKey = values[1]?.trim();
    if (athleteId == null ||
        athleteId.isEmpty ||
        apiKey == null ||
        apiKey.isEmpty) {
      return null;
    }
    return IntervalsCredentials(athleteId: athleteId, apiKey: apiKey);
  }

  Future<void> save(IntervalsCredentials credentials) async {
    await Future.wait([
      _storage.write(
        key: _athleteIdKey,
        value: credentials.athleteId.trim(),
      ),
      _storage.write(key: _apiKeyKey, value: credentials.apiKey.trim()),
    ]);
  }
}
