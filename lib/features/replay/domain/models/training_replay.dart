import '../../../heart_rate/domain/models/heart_rate_models.dart';
import '../../../training/domain/models/training_models.dart';

enum HeartRateZone { zone1, zone2, zone3, zone4, zone5 }

extension HeartRateZoneLabel on HeartRateZone {
  String get label => switch (this) {
        HeartRateZone.zone1 => 'Z1',
        HeartRateZone.zone2 => 'Z2',
        HeartRateZone.zone3 => 'Z3',
        HeartRateZone.zone4 => 'Z4',
        HeartRateZone.zone5 => 'Z5',
      };
}

final class HeartRateZoneClassifier {
  const HeartRateZoneClassifier(this.referenceMaximumBpm)
      : assert(referenceMaximumBpm > 0);

  /// The athlete-configured maximum can replace this value in a later release.
  final int referenceMaximumBpm;

  HeartRateZone classify(int bpm) {
    final ratio = bpm / referenceMaximumBpm;
    if (ratio >= .9) return HeartRateZone.zone5;
    if (ratio >= .8) return HeartRateZone.zone4;
    if (ratio >= .7) return HeartRateZone.zone3;
    if (ratio >= .6) return HeartRateZone.zone2;
    return HeartRateZone.zone1;
  }
}

final class ReplayHeartRatePoint {
  const ReplayHeartRatePoint({
    required this.timestamp,
    required this.elapsed,
    required this.bpm,
    required this.zone,
  });

  final DateTime timestamp;
  final Duration elapsed;
  final int bpm;
  final HeartRateZone zone;
}

final class HeartRateZoneStat {
  const HeartRateZoneStat({
    required this.zone,
    required this.duration,
    required this.percentage,
  });

  final HeartRateZone zone;
  final Duration duration;
  final double percentage;
}

final class ReplaySegment {
  const ReplaySegment({
    required this.stationId,
    required this.sequenceIndex,
    required this.type,
    required this.name,
    required this.start,
    required this.end,
    required this.averageHeartRate,
    required this.maximumHeartRate,
  });

  final int stationId;
  final int sequenceIndex;
  final StationType type;
  final String name;
  final Duration start;
  final Duration end;
  final int? averageHeartRate;
  final int? maximumHeartRate;

  Duration get duration => end - start;

  bool contains(Duration elapsed) => elapsed >= start && elapsed < end;
}

/// UI-independent replay aggregate. It can also produce a compact, versioned
/// payload for future local or remote AI analysis.
final class TrainingReplay {
  const TrainingReplay({
    required this.sessionId,
    required this.title,
    required this.startedAt,
    required this.duration,
    required this.averageHeartRate,
    required this.maximumHeartRate,
    required this.zoneReferenceMaximumBpm,
    required this.points,
    required this.zoneStats,
    required this.segments,
  });

  factory TrainingReplay.build({
    required TrainingSession session,
    required List<StationRecord> stations,
    required List<HeartRateSample> samples,
    int? zoneReferenceMaximumBpm,
  }) {
    final startedAt = session.startedAt;
    if (startedAt == null) {
      throw StateError('训练缺少开始时间，无法生成回放');
    }
    final orderedSamples = [...samples]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final summary = HeartRateSummary.fromSamples(orderedSamples);
    final endedAt = session.endedAt ??
        (session.totalDuration == null
            ? (orderedSamples.isEmpty
                ? startedAt
                : orderedSamples.last.timestamp)
            : startedAt.add(session.totalDuration!));
    final calculatedDuration = endedAt.isAfter(startedAt)
        ? endedAt.difference(startedAt)
        : Duration.zero;
    final duration =
        session.totalDuration != null && session.totalDuration! > Duration.zero
            ? session.totalDuration!
            : calculatedDuration;
    final referenceMaximum = zoneReferenceMaximumBpm ?? summary?.maximum ?? 1;
    final classifier = HeartRateZoneClassifier(referenceMaximum);
    final points = orderedSamples
        .where(
          (sample) =>
              !sample.timestamp.isBefore(startedAt) &&
              !sample.timestamp.isAfter(startedAt.add(duration)),
        )
        .map(
          (sample) => ReplayHeartRatePoint(
            timestamp: sample.timestamp,
            elapsed: sample.timestamp.difference(startedAt),
            bpm: sample.bpm,
            zone: classifier.classify(sample.bpm),
          ),
        )
        .toList(growable: false);

    final replaySegments = <ReplaySegment>[];
    for (final station in stations) {
      if (station.startedAt == null || station.endedAt == null) continue;
      final rawStart = station.startedAt!.difference(startedAt);
      final rawEnd = station.endedAt!.difference(startedAt);
      final start = _clampDuration(rawStart, duration);
      final end = _clampDuration(rawEnd, duration);
      if (end <= start) continue;
      final stationSummary = HeartRateSummary.fromSamples(
        orderedSamples.where(
          (sample) =>
              !sample.timestamp.isBefore(station.startedAt!) &&
              sample.timestamp.isBefore(station.endedAt!),
        ),
      );
      replaySegments.add(
        ReplaySegment(
          stationId: station.id,
          sequenceIndex: station.sequenceIndex,
          type: station.type,
          name: station.displayName,
          start: start,
          end: end,
          averageHeartRate: stationSummary?.average,
          maximumHeartRate: stationSummary?.maximum,
        ),
      );
    }
    replaySegments.sort((a, b) => a.start.compareTo(b.start));

    return TrainingReplay(
      sessionId: session.id,
      title: session.title,
      startedAt: startedAt,
      duration: duration,
      averageHeartRate: summary?.average,
      maximumHeartRate: summary?.maximum,
      zoneReferenceMaximumBpm: referenceMaximum,
      points: List.unmodifiable(points),
      zoneStats: _calculateZoneStats(points, duration),
      segments: List.unmodifiable(replaySegments),
    );
  }

  final int sessionId;
  final String title;
  final DateTime startedAt;
  final Duration duration;
  final int? averageHeartRate;
  final int? maximumHeartRate;
  final int zoneReferenceMaximumBpm;
  final List<ReplayHeartRatePoint> points;
  final List<HeartRateZoneStat> zoneStats;
  final List<ReplaySegment> segments;

  ReplaySegment? segmentAt(Duration elapsed) {
    for (final segment in segments) {
      if (segment.contains(elapsed)) return segment;
    }
    return null;
  }

  int? heartRateAt(Duration elapsed) {
    if (points.isEmpty) return null;
    const freshness = Duration(seconds: 15);
    if (elapsed <= points.first.elapsed) {
      return points.first.elapsed - elapsed <= freshness
          ? points.first.bpm
          : null;
    }
    if (elapsed >= points.last.elapsed) {
      return elapsed - points.last.elapsed <= freshness
          ? points.last.bpm
          : null;
    }
    var low = 0;
    var high = points.length - 1;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (points[middle].elapsed <= elapsed) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final before = points[low];
    final after = points[high];
    final interval = (after.elapsed - before.elapsed).inMilliseconds;
    if (interval <= 0) return before.bpm;
    if (interval > const Duration(seconds: 30).inMilliseconds) {
      if (elapsed - before.elapsed <= freshness) return before.bpm;
      if (after.elapsed - elapsed <= freshness) return after.bpm;
      return null;
    }
    final progress = (elapsed - before.elapsed).inMilliseconds / interval;
    return (before.bpm + (after.bpm - before.bpm) * progress).round();
  }

  HeartRateZone? zoneAt(Duration elapsed) {
    final bpm = heartRateAt(elapsed);
    return bpm == null
        ? null
        : HeartRateZoneClassifier(zoneReferenceMaximumBpm).classify(bpm);
  }

  Map<String, Object?> toAnalysisPayload({int maxSamples = 300}) {
    if (maxSamples <= 0) {
      throw ArgumentError.value(maxSamples, 'maxSamples', '必须大于 0');
    }
    final stride =
        points.length <= maxSamples ? 1 : (points.length / maxSamples).ceil();
    final sampled = <Map<String, Object?>>[];
    for (var index = 0; index < points.length; index += stride) {
      final point = points[index];
      sampled.add({
        'elapsed_seconds': point.elapsed.inMilliseconds / 1000,
        'bpm': point.bpm,
        'zone': point.zone.label,
      });
    }
    return {
      'schema_version': 1,
      'session_id': sessionId,
      'title': title,
      'started_at': startedAt.toUtc().toIso8601String(),
      'duration_seconds': duration.inMilliseconds / 1000,
      'heart_rate': {
        'average_bpm': averageHeartRate,
        'maximum_bpm': maximumHeartRate,
        'zone_reference_maximum_bpm': zoneReferenceMaximumBpm,
        'sample_count': points.length,
        'zones': [
          for (final stat in zoneStats)
            {
              'zone': stat.zone.label,
              'duration_seconds': stat.duration.inMilliseconds / 1000,
              'percentage': stat.percentage,
            },
        ],
        'samples': sampled,
      },
      'segments': [
        for (final segment in segments)
          {
            'sequence': segment.sequenceIndex + 1,
            'type': segment.type.name,
            'name': segment.name,
            'start_seconds': segment.start.inMilliseconds / 1000,
            'end_seconds': segment.end.inMilliseconds / 1000,
            'average_bpm': segment.averageHeartRate,
            'maximum_bpm': segment.maximumHeartRate,
          },
      ],
    };
  }
}

Duration _clampDuration(Duration value, Duration maximum) {
  if (value < Duration.zero) return Duration.zero;
  if (value > maximum) return maximum;
  return value;
}

List<HeartRateZoneStat> _calculateZoneStats(
  List<ReplayHeartRatePoint> points,
  Duration workoutDuration,
) {
  final milliseconds = {
    for (final zone in HeartRateZone.values) zone: 0,
  };
  if (points.isEmpty || workoutDuration <= Duration.zero) {
    return HeartRateZone.values
        .map(
          (zone) => HeartRateZoneStat(
            zone: zone,
            duration: Duration.zero,
            percentage: 0,
          ),
        )
        .toList(growable: false);
  }

  final gaps = <int>[];
  for (var index = 0; index < points.length - 1; index++) {
    final gap =
        (points[index + 1].elapsed - points[index].elapsed).inMilliseconds;
    if (gap > 0 && gap <= const Duration(seconds: 30).inMilliseconds) {
      gaps.add(gap);
    }
  }
  gaps.sort();
  final typicalGap = gaps.isEmpty ? 1000 : gaps[gaps.length ~/ 2];
  const maximumGap = 30000;
  for (var index = 0; index < points.length; index++) {
    final point = points[index];
    final available =
        workoutDuration.inMilliseconds - point.elapsed.inMilliseconds;
    if (available <= 0) continue;
    final rawGap = index + 1 < points.length
        ? (points[index + 1].elapsed - point.elapsed).inMilliseconds
        : typicalGap;
    final contribution = rawGap.clamp(0, maximumGap).clamp(0, available);
    milliseconds[point.zone] = milliseconds[point.zone]! + contribution;
  }
  final covered = milliseconds.values.fold<int>(0, (sum, value) => sum + value);
  return HeartRateZone.values
      .map(
        (zone) => HeartRateZoneStat(
          zone: zone,
          duration: Duration(milliseconds: milliseconds[zone]!),
          percentage: covered == 0 ? 0 : milliseconds[zone]! / covered,
        ),
      )
      .toList(growable: false);
}
