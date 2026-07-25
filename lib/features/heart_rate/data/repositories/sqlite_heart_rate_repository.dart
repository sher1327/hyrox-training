import '../../domain/models/heart_rate_models.dart';
import '../../domain/repositories/heart_rate_repository.dart';
import '../dao/heart_rate_dao.dart';

final class SqliteHeartRateRepository implements HeartRateRepository {
  const SqliteHeartRateRepository(this.dao);

  final HeartRateDao dao;

  @override
  Future<List<HeartRateSample>> listSamples(int sessionId) async {
    final rows = await dao.listSamples(sessionId);
    return rows
        .map(
          (row) => HeartRateSample(
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              row['timestamp_ms']! as int,
              isUtc: true,
            ),
            bpm: row['heart_rate_bpm']! as int,
            source: row['source']! as String,
            importBatchId: row['import_batch_id']! as int,
          ),
        )
        .toList();
  }

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
}
