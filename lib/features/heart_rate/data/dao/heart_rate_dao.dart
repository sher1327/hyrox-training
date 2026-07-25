import 'package:sqflite/sqflite.dart';

import '../../domain/models/heart_rate_models.dart';

final class HeartRateDao {
  const HeartRateDao(this.db);

  final Database db;

  Future<int> replaceSamples({
    required int sessionId,
    required List<HeartRateSample> samples,
    required String source,
    String? externalActivityId,
    String? externalActivityName,
    String? fileName,
  }) async {
    if (samples.isEmpty) throw ArgumentError('心率采样不能为空');
    final summary = HeartRateSummary.fromSamples(samples)!;
    return db.transaction((txn) async {
      await txn.update(
        'heart_rate_import',
        {'is_active': 0},
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      final importedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      final importBatchId = await txn.insert('heart_rate_import', {
        'session_id': sessionId,
        'source': source,
        'external_activity_id': externalActivityId,
        'external_activity_name': externalActivityName,
        'file_name': fileName,
        'imported_at_ms': importedAt,
        'sample_count': summary.sampleCount,
        'avg_heart_rate': summary.average,
        'max_heart_rate': summary.maximum,
        'is_active': 1,
      });
      final batch = txn.batch();
      for (final sample in samples) {
        batch.insert(
          'heart_rate_sample',
          {
            'session_id': sessionId,
            'import_batch_id': importBatchId,
            'timestamp_ms': sample.timestamp.toUtc().millisecondsSinceEpoch,
            'heart_rate_bpm': sample.bpm,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      final updated = await txn.update(
        'training_session',
        {
          'avg_heart_rate': summary.average,
          'max_heart_rate': summary.maximum,
          'heart_rate_source': source,
          'heart_rate_external_id': externalActivityId,
          'heart_rate_sample_count': summary.sampleCount,
          'heart_rate_imported_at_ms': importedAt,
          'updated_at_ms': importedAt,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      if (updated != 1) throw StateError('训练记录不存在');
      return importBatchId;
    });
  }

  Future<List<Map<String, Object?>>> listSamples(int sessionId) => db.rawQuery(
        '''SELECT sample.*, import_batch.source
           FROM heart_rate_sample sample
           JOIN heart_rate_import import_batch
             ON import_batch.id = sample.import_batch_id
           WHERE sample.session_id = ? AND import_batch.is_active = 1
           ORDER BY sample.timestamp_ms ASC''',
        [sessionId],
      );
}
