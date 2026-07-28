import 'package:flutter/services.dart';

final class BackupDocumentWriter {
  const BackupDocumentWriter();

  static const _channel = MethodChannel('hyrox/data_backup');

  /// Opens Android's system document creator and streams [sourcePath] to the
  /// URI chosen by the user. Returns false when the picker is cancelled.
  Future<bool> save({
    required String sourcePath,
    required String suggestedName,
  }) async {
    final saved = await _channel.invokeMethod<bool>('saveBackup', {
      'sourcePath': sourcePath,
      'suggestedName': suggestedName,
    });
    return saved ?? false;
  }
}
