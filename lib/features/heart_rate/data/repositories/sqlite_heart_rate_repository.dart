import '../../domain/models/heart_rate_models.dart';
import '../../domain/repositories/heart_rate_repository.dart';
import '../dao/heart_rate_dao.dart';

final class SqliteHeartRateRepository implements HeartRateRepository {
  const SqliteHeartRateRepository(this.dao);

  final HeartRateDao dao;

  @override
  Future<List<HeartRateImportBatch>> listBatches(int sessionId) async =>
      (await dao.listBatches(sessionId)).map(_batchFromRow).toList();

  @override
  Future<List<HeartRateSample>> listSamples(int sessionId) async =>
      (await dao.listSamples(sessionId)).map(_sampleFromRow).toList();

  @override
  Future<List<HeartRateSample>> listSamplesByBatch(int importBatchId) async =>
      (await dao.listSamplesByBatch(importBatchId))
          .map(_sampleFromRow)
          .toList();

  @override
  Future<int> replaceSamples({
    required int sessionId,
    required List<HeartRateSample> samples,
    required String source,
    String? externalActivityId,
    String? externalActivityName,
    String? fileName,
  }) =>
      dao.replaceSamples(
        sessionId: sessionId,
        samples: samples,
        source: source,
        externalActivityId: externalActivityId,
        externalActivityName: externalActivityName,
        fileName: fileName,
      );

  @override
  Future<int> appendLiveSamples({
    required int sessionId,
    required String deviceId,
    required String deviceName,
    required List<HeartRateSample> samples,
  }) =>
      dao.appendLiveSamples(
        sessionId: sessionId,
        deviceId: deviceId,
        deviceName: deviceName,
        samples: samples,
      );

  @override
  Future<void> setActiveBatch({
    required int sessionId,
    required int importBatchId,
  }) =>
      dao.setActiveBatch(
        sessionId: sessionId,
        importBatchId: importBatchId,
      );
}

HeartRateSample _sampleFromRow(Map<String, Object?> row) => HeartRateSample(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        row['timestamp_ms']! as int,
        isUtc: true,
      ),
      bpm: row['heart_rate_bpm']! as int,
      source: row['source']! as String,
      importBatchId: row['import_batch_id']! as int,
    );

HeartRateImportBatch _batchFromRow(Map<String, Object?> row) =>
    HeartRateImportBatch(
      id: row['id']! as int,
      sessionId: row['session_id']! as int,
      source: row['source']! as String,
      externalActivityId: row['external_activity_id'] as String?,
      externalActivityName: row['external_activity_name'] as String?,
      fileName: row['file_name'] as String?,
      importedAt: DateTime.fromMillisecondsSinceEpoch(
        row['imported_at_ms']! as int,
        isUtc: true,
      ),
      sampleCount: row['sample_count']! as int,
      average: row['avg_heart_rate']! as int,
      maximum: row['max_heart_rate']! as int,
      isActive: row['is_active'] == 1,
    );
