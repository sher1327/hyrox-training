enum TrainingMode { single, double, relay }

enum TrainingStatus { draft, inProgress, completed, cancelled }

enum SegmentStatus { pending, active, completed, skipped }

enum AthleteAssignment { self, partner, both }

enum StationType {
  run,
  skiErg,
  sledPush,
  sledPull,
  burpeeBroadJump,
  row,
  farmerCarry,
  sandbagLunge,
  wallBall,
}

extension StationTypeLabel on StationType {
  String get label => switch (this) {
        StationType.run => 'RUN',
        StationType.skiErg => 'SKI ERG',
        StationType.sledPush => 'SLED PUSH',
        StationType.sledPull => 'SLED PULL',
        StationType.burpeeBroadJump => 'BURPEE BROAD JUMP',
        StationType.row => 'ROW',
        StationType.farmerCarry => 'FARMER CARRY',
        StationType.sandbagLunge => 'SANDBAG LUNGE',
        StationType.wallBall => 'WALL BALL',
      };
}

final class TrainingSession {
  const TrainingSession({
    required this.id,
    required this.mode,
    required this.title,
    required this.status,
    this.partnerName,
    this.partnerName2,
    this.partnerName3,
    this.startedAt,
    this.endedAt,
    this.totalDuration,
    this.avgHeartRate,
    this.maxHeartRate,
    this.heartRateSource,
    this.heartRateExternalId,
    this.heartRateSampleCount,
    this.heartRateImportedAt,
    this.note,
    this.templateId,
    this.templateNameSnapshot,
  });

  final int id;
  final TrainingMode mode;
  final String title;
  final String? partnerName;
  final String? partnerName2;
  final String? partnerName3;
  final TrainingStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Duration? totalDuration;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final String? heartRateSource;
  final String? heartRateExternalId;
  final int? heartRateSampleCount;
  final DateTime? heartRateImportedAt;
  final String? note;
  final int? templateId;
  final String? templateNameSnapshot;

  List<String> get teammateNames => [
        partnerName,
        partnerName2,
        partnerName3,
      ].whereType<String>().where((name) => name.isNotEmpty).toList();
}

final class StationRecord {
  const StationRecord({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.sequenceIndex,
    required this.status,
    this.runNumber,
    this.startedAt,
    this.endedAt,
    this.duration,
    this.athlete,
    this.athleteName,
    this.distanceMeters,
    this.resistanceLevel,
    this.weightKg,
    this.repetitions,
    this.transitionStartedAt,
    this.transitionEndedAt,
    this.transitionDuration,
  });

  final int id;
  final int sessionId;
  final StationType type;
  final int? runNumber;
  final int sequenceIndex;
  final SegmentStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Duration? duration;
  final AthleteAssignment? athlete;
  final String? athleteName;
  final int? distanceMeters;
  final int? resistanceLevel;
  final double? weightKg;
  final int? repetitions;
  final DateTime? transitionStartedAt;
  final DateTime? transitionEndedAt;
  final Duration? transitionDuration;

  bool get isTransitionActive =>
      transitionStartedAt != null && transitionEndedAt == null;

  String get displayName {
    final details = <String>[];
    if (resistanceLevel != null) details.add('阻力 $resistanceLevel');
    if (weightKg != null) {
      final weight = weightKg == weightKg!.roundToDouble()
          ? weightKg!.toInt().toString()
          : weightKg!.toStringAsFixed(1);
      details.add(
          type == StationType.farmerCarry ? '2 × $weight kg' : '$weight kg');
    }
    if (distanceMeters != null) details.add('$distanceMeters m');
    if (repetitions != null) details.add('$repetitions 次');
    final name =
        type == StationType.run ? '${type.label} $runNumber' : type.label;
    return details.isEmpty ? name : '$name · ${details.join(' · ')}';
  }

  StationRecord copyWith({
    SegmentStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    Duration? duration,
    AthleteAssignment? athlete,
    String? athleteName,
  }) {
    return StationRecord(
      id: id,
      sessionId: sessionId,
      type: type,
      sequenceIndex: sequenceIndex,
      status: status ?? this.status,
      runNumber: runNumber,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      athlete: athlete ?? this.athlete,
      athleteName: athleteName ?? this.athleteName,
      distanceMeters: distanceMeters,
      resistanceLevel: resistanceLevel,
      weightKg: weightKg,
      repetitions: repetitions,
      transitionStartedAt: transitionStartedAt,
      transitionEndedAt: transitionEndedAt,
      transitionDuration: transitionDuration,
    );
  }
}

const standardHyroxFlow = <({StationType type, int? runNumber})>[
  (type: StationType.run, runNumber: 1),
  (type: StationType.skiErg, runNumber: null),
  (type: StationType.run, runNumber: 2),
  (type: StationType.sledPush, runNumber: null),
  (type: StationType.run, runNumber: 3),
  (type: StationType.sledPull, runNumber: null),
  (type: StationType.run, runNumber: 4),
  (type: StationType.burpeeBroadJump, runNumber: null),
  (type: StationType.run, runNumber: 5),
  (type: StationType.row, runNumber: null),
  (type: StationType.run, runNumber: 6),
  (type: StationType.farmerCarry, runNumber: null),
  (type: StationType.run, runNumber: 7),
  (type: StationType.sandbagLunge, runNumber: null),
  (type: StationType.run, runNumber: 8),
  (type: StationType.wallBall, runNumber: null),
];
