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
      await _insertSamples(
        txn,
        sessionId: sessionId,
        importBatchId: importBatchId,
        samples: samples,
      );
      await _updateSessionSummary(
        txn,
        sessionId: sessionId,
        source: source,
        externalActivityId: externalActivityId,
        summary: summary,
        importedAt: importedAt,
      );
      return importBatchId;
    });
  }

  Future<int> appendLiveSamples({
    required int sessionId,
    required String deviceId,
    required String deviceName,
    required List<HeartRateSample> samples,
  }) async {
    if (samples.isEmpty) throw ArgumentError('心率采样不能为空');
    return db.transaction((txn) async {
      final existing = await txn.query(
        'heart_rate_import',
        where: 'session_id = ? AND source = ? AND external_activity_id = ?',
        whereArgs: [sessionId, HeartRateSources.ble, deviceId],
        orderBy: 'imported_at_ms DESC',
        limit: 1,
      );
      late final int importBatchId;
      late final bool isActive;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      if (existing.isEmpty) {
        final active = await txn.query(
          'heart_rate_import',
          columns: ['id'],
          where: 'session_id = ? AND is_active = 1',
          whereArgs: [sessionId],
          limit: 1,
        );
        isActive = active.isEmpty;
        final initial = HeartRateSummary.fromSamples(samples)!;
        importBatchId = await txn.insert('heart_rate_import', {
          'session_id': sessionId,
          'source': HeartRateSources.ble,
          'external_activity_id': deviceId,
          'external_activity_name': deviceName,
          'imported_at_ms': now,
          'sample_count': initial.sampleCount,
          'avg_heart_rate': initial.average,
          'max_heart_rate': initial.maximum,
          'is_active': isActive ? 1 : 0,
        });
      } else {
        importBatchId = existing.single['id']! as int;
        isActive = existing.single['is_active'] == 1;
      }

      await _insertSamples(
        txn,
        sessionId: sessionId,
        importBatchId: importBatchId,
        samples: samples,
      );
      final aggregate = (await txn.rawQuery(
        '''SELECT COUNT(*) AS sample_count,
                  ROUND(AVG(heart_rate_bpm)) AS avg_heart_rate,
                  MAX(heart_rate_bpm) AS max_heart_rate
           FROM heart_rate_sample
           WHERE import_batch_id = ?''',
        [importBatchId],
      ))
          .single;
      final summary = HeartRateSummary(
        average: (aggregate['avg_heart_rate']! as num).round(),
        maximum: aggregate['max_heart_rate']! as int,
        sampleCount: aggregate['sample_count']! as int,
      );
      await txn.update(
        'heart_rate_import',
        {
          'sample_count': summary.sampleCount,
          'avg_heart_rate': summary.average,
          'max_heart_rate': summary.maximum,
        },
        where: 'id = ?',
        whereArgs: [importBatchId],
      );
      if (isActive) {
        await _updateSessionSummary(
          txn,
          sessionId: sessionId,
          source: HeartRateSources.ble,
          externalActivityId: deviceId,
          summary: summary,
          importedAt: now,
        );
      }
      return importBatchId;
    });
  }

  Future<List<Map<String, Object?>>> listBatches(int sessionId) => db.query(
        'heart_rate_import',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'is_active DESC, imported_at_ms DESC',
      );

  Future<List<Map<String, Object?>>> listSamples(int sessionId) => db.rawQuery(
        '''SELECT sample.*, import_batch.source
           FROM heart_rate_sample sample
           JOIN heart_rate_import import_batch
             ON import_batch.id = sample.import_batch_id
           WHERE sample.session_id = ? AND import_batch.is_active = 1
           ORDER BY sample.timestamp_ms ASC''',
        [sessionId],
      );

  Future<List<Map<String, Object?>>> listSamplesByBatch(int importBatchId) =>
      db.rawQuery(
        '''SELECT sample.*, import_batch.source
           FROM heart_rate_sample sample
           JOIN heart_rate_import import_batch
             ON import_batch.id = sample.import_batch_id
           WHERE sample.import_batch_id = ?
           ORDER BY sample.timestamp_ms ASC''',
        [importBatchId],
      );

  Future<void> setActiveBatch({
    required int sessionId,
    required int importBatchId,
  }) =>
      db.transaction((txn) async {
        final rows = await txn.query(
          'heart_rate_import',
          where: 'id = ? AND session_id = ?',
          whereArgs: [importBatchId, sessionId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('心率来源不存在');
        final row = rows.single;
        await txn.update(
          'heart_rate_import',
          {'is_active': 0},
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        await txn.update(
          'heart_rate_import',
          {'is_active': 1},
          where: 'id = ?',
          whereArgs: [importBatchId],
        );
        await _updateSessionSummary(
          txn,
          sessionId: sessionId,
          source: row['source']! as String,
          externalActivityId: row['external_activity_id'] as String?,
          summary: HeartRateSummary(
            average: row['avg_heart_rate']! as int,
            maximum: row['max_heart_rate']! as int,
            sampleCount: row['sample_count']! as int,
          ),
          importedAt: row['imported_at_ms']! as int,
        );
      });

  Future<void> _insertSamples(
    DatabaseExecutor executor, {
    required int sessionId,
    required int importBatchId,
    required List<HeartRateSample> samples,
  }) async {
    final batch = executor.batch();
    for (final sample in samples) {
      batch.insert(
        'heart_rate_sample',
        {
          'session_id': sessionId,
          'import_batch_id': importBatchId,
          'timestamp_ms': sample.timestamp.toUtc().millisecondsSinceEpoch,
          'heart_rate_bpm': sample.bpm,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _updateSessionSummary(
    DatabaseExecutor executor, {
    required int sessionId,
    required String source,
    required String? externalActivityId,
    required HeartRateSummary summary,
    required int importedAt,
  }) async {
    final updated = await executor.update(
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
  }
}
