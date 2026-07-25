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

  Future<List<HeartRateSample>> listSamples(int sessionId);
}
