import '../../../training/domain/models/training_models.dart';

final class HeartRateSample {
  const HeartRateSample({
    required this.timestamp,
    required this.bpm,
    this.source,
    this.importBatchId,
  });

  final DateTime timestamp;
  final int bpm;
  final String? source;
  final int? importBatchId;
}

final class HeartRateImportBatch {
  const HeartRateImportBatch({
    required this.id,
    required this.sessionId,
    required this.source,
    required this.importedAt,
    required this.sampleCount,
    required this.average,
    required this.maximum,
    required this.isActive,
    this.externalActivityId,
    this.externalActivityName,
    this.fileName,
  });

  final int id;
  final int sessionId;
  final String source;
  final String? externalActivityId;
  final String? externalActivityName;
  final String? fileName;
  final DateTime importedAt;
  final int sampleCount;
  final int average;
  final int maximum;
  final bool isActive;
}

final class HeartRateSummary {
  const HeartRateSummary({
    required this.average,
    required this.maximum,
    required this.sampleCount,
  });

  final int average;
  final int maximum;
  final int sampleCount;

  static HeartRateSummary? fromSamples(Iterable<HeartRateSample> samples) {
    var count = 0;
    var total = 0;
    var maximum = 0;
    for (final sample in samples) {
      count++;
      total += sample.bpm;
      if (sample.bpm > maximum) maximum = sample.bpm;
    }
    if (count == 0) return null;
    return HeartRateSummary(
      average: (total / count).round(),
      maximum: maximum,
      sampleCount: count,
    );
  }
}

final class HeartRateAnalysis {
  const HeartRateAnalysis({
    required this.full,
    required this.byStationId,
    required this.samples,
  });

  final HeartRateSummary? full;
  final Map<int, HeartRateSummary> byStationId;
  final List<HeartRateSample> samples;

  factory HeartRateAnalysis.build(
    List<HeartRateSample> samples,
    List<StationRecord> stations,
  ) {
    final ordered = [...samples]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final summaries = <int, HeartRateSummary>{};
    for (final station in stations) {
      final start = station.startedAt;
      final end = station.endedAt;
      if (start == null || end == null || !end.isAfter(start)) continue;
      final summary = HeartRateSummary.fromSamples(
        ordered.where(
          (sample) =>
              !sample.timestamp.isBefore(start) &&
              sample.timestamp.isBefore(end),
        ),
      );
      if (summary != null) summaries[station.id] = summary;
    }
    return HeartRateAnalysis(
      full: HeartRateSummary.fromSamples(ordered),
      byStationId: summaries,
      samples: ordered,
    );
  }
}

final class HeartRateImportResult {
  const HeartRateImportResult({
    required this.source,
    required this.sampleCount,
    required this.average,
    required this.maximum,
    required this.importBatchId,
    this.externalActivityId,
  });

  final String source;
  final int sampleCount;
  final int average;
  final int maximum;
  final int importBatchId;
  final String? externalActivityId;
}

abstract final class HeartRateSources {
  static const fit = 'fit';
  static const intervalsIcu = 'intervals_icu';
}
