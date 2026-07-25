import 'package:sqflite/sqflite.dart';

import '../../domain/models/heart_rate_models.dart';

final class HeartRateDao {
  const HeartRateDao(this.db);

  final Database db;

  Future<void> replaceSamples({
    required int sessionId,
    required List<HeartRateSample> samples,
    required String source,
    String? externalActivityId,
  }) async {
    if (samples.isEmpty) throw ArgumentError('心率采样不能为空');
    final summary = HeartRateSummary.fromSamples(samples)!;
    await db.transaction((txn) async {
      await txn.delete(
        'heart_rate_sample',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      final batch = txn.batch();
      for (final sample in samples) {
        batch.insert(
          'heart_rate_sample',
          {
            'session_id': sessionId,
            'timestamp_ms': sample.timestamp.toUtc().millisecondsSinceEpoch,
            'heart_rate_bpm': sample.bpm,
            'source': source,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      final importedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
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
    });
  }

  Future<List<Map<String, Object?>>> listSamples(int sessionId) => db.query(
        'heart_rate_sample',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp_ms ASC',
      );
}
