enum TrainingMode { single, double, relay }

enum TrainingStatus { draft, inProgress, completed, cancelled }

enum TrainingFeeling { veryBad, bad, neutral, good, veryGood }

extension TrainingFeelingLabel on TrainingFeeling {
  String get label => switch (this) {
        TrainingFeeling.veryBad => '很差',
        TrainingFeeling.bad => '较差',
        TrainingFeeling.neutral => '一般',
        TrainingFeeling.good => '不错',
        TrainingFeeling.veryGood => '很好',
      };

  String get databaseValue => switch (this) {
        TrainingFeeling.veryBad => 'very_bad',
        TrainingFeeling.bad => 'bad',
        TrainingFeeling.neutral => 'neutral',
        TrainingFeeling.good => 'good',
        TrainingFeeling.veryGood => 'very_good',
      };

  static TrainingFeeling? fromDatabase(String? value) => switch (value) {
        'very_bad' => TrainingFeeling.veryBad,
        'bad' => TrainingFeeling.bad,
        'neutral' => TrainingFeeling.neutral,
        'good' => TrainingFeeling.good,
        'very_good' => TrainingFeeling.veryGood,
        _ => null,
      };
}

final class TrainingReflection {
  const TrainingReflection({
    required this.perceivedEffort,
    required this.feeling,
    required this.note,
  });

  final int perceivedEffort;
  final TrainingFeeling feeling;
  final String note;
}

enum SegmentStatus { pending, active, completed, skipped }

enum StationRecordOrigin { template, adHoc }

enum TrainingSegmentKind { station, rest, warmup, cooldown }

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
    this.perceivedEffort,
    this.feeling,
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
  final int? perceivedEffort;
  final TrainingFeeling? feeling;
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
    this.plannedSequenceIndex,
    this.origin = StationRecordOrigin.template,
    this.segmentKind = TrainingSegmentKind.station,
    this.runNumber,
    this.startedAt,
    this.endedAt,
    this.duration,
    this.athlete,
    this.athleteName,
    this.targetDistanceMeters,
    this.targetResistanceLevel,
    this.targetWeightKg,
    this.targetRepetitions,
    this.actualDistanceMeters,
    this.actualResistanceLevel,
    this.actualWeightKg,
    this.actualRepetitions,
    this.transitionStartedAt,
    this.transitionEndedAt,
    this.transitionDuration,
    this.skipReason,
  });

  final int id;
  final int sessionId;
  final StationType type;
  final int? runNumber;
  final int? plannedSequenceIndex;
  final int sequenceIndex;
  final StationRecordOrigin origin;
  final SegmentStatus status;
  final TrainingSegmentKind segmentKind;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Duration? duration;
  final AthleteAssignment? athlete;
  final String? athleteName;
  final int? targetDistanceMeters;
  final int? targetResistanceLevel;
  final double? targetWeightKg;
  final int? targetRepetitions;
  final int? actualDistanceMeters;
  final int? actualResistanceLevel;
  final double? actualWeightKg;
  final int? actualRepetitions;
  final DateTime? transitionStartedAt;
  final DateTime? transitionEndedAt;
  final Duration? transitionDuration;
  final String? skipReason;

  bool get isAdHoc => origin == StationRecordOrigin.adHoc;

  bool get wasRemovedBeforeStart =>
      status == SegmentStatus.skipped && startedAt == null;

  bool get isTransitionActive =>
      transitionStartedAt != null && transitionEndedAt == null;

  bool get hasActualPerformance =>
      actualDistanceMeters != null ||
      actualResistanceLevel != null ||
      actualWeightKg != null ||
      actualRepetitions != null;

  bool get actualMatchesTarget =>
      actualDistanceMeters == targetDistanceMeters &&
      actualResistanceLevel == targetResistanceLevel &&
      actualWeightKg == targetWeightKg &&
      actualRepetitions == targetRepetitions;

  String? get actualSpecification {
    if (!hasActualPerformance) return null;
    if (actualMatchesTarget) return '实际：按计划完成';
    final details = <String>[];
    if (actualResistanceLevel != null) {
      details.add('阻力 $actualResistanceLevel');
    }
    if (actualWeightKg != null) {
      final value = actualWeightKg == actualWeightKg!.roundToDouble()
          ? actualWeightKg!.toInt().toString()
          : actualWeightKg!.toStringAsFixed(1);
      details
          .add(type == StationType.farmerCarry ? '2 × $value kg' : '$value kg');
    }
    if (actualDistanceMeters != null) details.add('$actualDistanceMeters m');
    if (actualRepetitions != null) details.add('$actualRepetitions 次');
    return details.isEmpty ? null : '实际：${details.join(' · ')}';
  }

  String get displayName {
    final details = <String>[];
    if (targetResistanceLevel != null) {
      details.add('阻力 $targetResistanceLevel');
    }
    if (targetWeightKg != null) {
      final weight = targetWeightKg == targetWeightKg!.roundToDouble()
          ? targetWeightKg!.toInt().toString()
          : targetWeightKg!.toStringAsFixed(1);
      details.add(
          type == StationType.farmerCarry ? '2 × $weight kg' : '$weight kg');
    }
    if (targetDistanceMeters != null) details.add('$targetDistanceMeters m');
    if (targetRepetitions != null) details.add('$targetRepetitions 次');
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
      plannedSequenceIndex: plannedSequenceIndex,
      origin: origin,
      status: status ?? this.status,
      segmentKind: segmentKind,
      runNumber: runNumber,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      athlete: athlete ?? this.athlete,
      athleteName: athleteName ?? this.athleteName,
      targetDistanceMeters: targetDistanceMeters,
      targetResistanceLevel: targetResistanceLevel,
      targetWeightKg: targetWeightKg,
      targetRepetitions: targetRepetitions,
      actualDistanceMeters: actualDistanceMeters,
      actualResistanceLevel: actualResistanceLevel,
      actualWeightKg: actualWeightKg,
      actualRepetitions: actualRepetitions,
      transitionStartedAt: transitionStartedAt,
      transitionEndedAt: transitionEndedAt,
      transitionDuration: transitionDuration,
      skipReason: skipReason,
    );
  }
}

final class StationActualPerformance {
  const StationActualPerformance({
    this.distanceMeters,
    this.resistanceLevel,
    this.weightKg,
    this.repetitions,
  });

  final int? distanceMeters;
  final int? resistanceLevel;
  final double? weightKg;
  final int? repetitions;

  factory StationActualPerformance.fromTarget(StationRecord station) =>
      StationActualPerformance(
        distanceMeters: station.targetDistanceMeters,
        resistanceLevel: station.targetResistanceLevel,
        weightKg: station.targetWeightKg,
        repetitions: station.targetRepetitions,
      );
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
