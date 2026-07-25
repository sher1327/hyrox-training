import '../../../training/domain/models/training_models.dart';
import '../models/heart_rate_models.dart';
import '../models/intervals_models.dart';
import '../repositories/heart_rate_repository.dart';
import '../../data/services/intervals_icu_client.dart';

final class HeartRateImportService {
  const HeartRateImportService({
    required HeartRateRepository repository,
    required IntervalsIcuClient intervalsClient,
  })  : _repository = repository,
        _intervalsClient = intervalsClient;

  final HeartRateRepository _repository;
  final IntervalsIcuClient _intervalsClient;

  Future<HeartRateImportResult> importFit({
    required TrainingSession session,
    required List<HeartRateSample> samples,
    required String fileName,
  }) =>
      _saveForSession(
        session: session,
        samples: samples,
        source: HeartRateSources.fit,
        externalActivityId: fileName,
        fileName: fileName,
      );

  Future<List<IntervalsActivity>> findIntervalsActivities({
    required TrainingSession session,
    required IntervalsCredentials credentials,
  }) async {
    final range = _sessionRange(session);
    final activities = await _intervalsClient.listActivities(
      credentials: credentials,
      oldest: range.$1,
      newest: range.$2,
    );
    return IntervalsActivityMatcher.overlappingSession(
      activities: activities,
      sessionStart: range.$1,
      sessionEnd: range.$2,
    );
  }

  Future<HeartRateImportResult> importIntervalsActivity({
    required TrainingSession session,
    required IntervalsCredentials credentials,
    required IntervalsActivity activity,
  }) async {
    final samples = await _intervalsClient.getHeartRateStream(
      credentials: credentials,
      activity: activity,
    );
    return _saveForSession(
      session: session,
      samples: samples,
      source: HeartRateSources.intervalsIcu,
      externalActivityId: activity.id,
      externalActivityName: activity.name,
    );
  }

  Future<HeartRateImportResult> _saveForSession({
    required TrainingSession session,
    required List<HeartRateSample> samples,
    required String source,
    required String externalActivityId,
    String? externalActivityName,
    String? fileName,
  }) async {
    final range = _sessionRange(session);
    final byTimestamp = <int, HeartRateSample>{};
    for (final sample in samples) {
      if (sample.timestamp.isBefore(range.$1) ||
          sample.timestamp.isAfter(range.$2)) {
        continue;
      }
      byTimestamp[sample.timestamp.toUtc().millisecondsSinceEpoch] = sample;
    }
    final cropped = byTimestamp.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (cropped.isEmpty) {
      throw StateError('心率记录与这场训练的时间范围没有重叠');
    }
    final summary = HeartRateSummary.fromSamples(cropped)!;
    final importBatchId = await _repository.replaceSamples(
      sessionId: session.id,
      samples: cropped,
      source: source,
      externalActivityId: externalActivityId,
      externalActivityName: externalActivityName,
      fileName: fileName,
    );
    return HeartRateImportResult(
      source: source,
      sampleCount: summary.sampleCount,
      average: summary.average,
      maximum: summary.maximum,
      importBatchId: importBatchId,
      externalActivityId: externalActivityId,
    );
  }

  (DateTime, DateTime) _sessionRange(TrainingSession session) {
    final start = session.startedAt;
    final end = session.endedAt;
    if (start == null || end == null || !end.isAfter(start)) {
      throw StateError('训练尚未结束，暂时不能导入心率');
    }
    return (start, end);
  }
}
