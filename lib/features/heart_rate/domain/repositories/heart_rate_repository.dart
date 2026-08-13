import '../models/heart_rate_models.dart';

abstract interface class HeartRateRepository {
  Future<int> replaceSamples({
    required int sessionId,
    required List<HeartRateSample> samples,
    required String source,
    String? externalActivityId,
    String? externalActivityName,
    String? fileName,
  });

  Future<int> appendLiveSamples({
    required int sessionId,
    required String deviceId,
    required String deviceName,
    required List<HeartRateSample> samples,
  });

  Future<List<HeartRateImportBatch>> listBatches(int sessionId);
  Future<List<HeartRateSample>> listSamples(int sessionId);
  Future<List<HeartRateSample>> listSamplesByBatch(int importBatchId);

  Future<void> setActiveBatch({
    required int sessionId,
    required int importBatchId,
  });
}
