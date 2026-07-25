import '../models/heart_rate_models.dart';

abstract interface class HeartRateRepository {
  Future<void> replaceSamples({
    required int sessionId,
    required List<HeartRateSample> samples,
    required String source,
    String? externalActivityId,
  });

  Future<List<HeartRateSample>> listSamples(int sessionId);
}
