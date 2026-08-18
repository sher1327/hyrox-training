enum Concept2Machine { rower, skierg }

extension Concept2MachineDisplay on Concept2Machine {
  String get apiValue => switch (this) {
        Concept2Machine.rower => 'rower',
        Concept2Machine.skierg => 'skierg',
      };

  String get label => switch (this) {
        Concept2Machine.rower => '划船',
        Concept2Machine.skierg => '滑雪',
      };
}

final class Concept2Credentials {
  const Concept2Credentials(this.accessToken);

  final String accessToken;
}

final class Concept2Interval {
  const Concept2Interval({
    required this.sequenceIndex,
    required this.kind,
    required this.timeTenths,
    required this.distanceMeters,
    this.restTimeTenths = 0,
    this.restDistanceMeters = 0,
    this.strokeRate,
    this.calories,
  });

  final int sequenceIndex;
  final String kind;
  final int timeTenths;
  final int distanceMeters;
  final int restTimeTenths;
  final int restDistanceMeters;
  final int? strokeRate;
  final int? calories;

  Duration get workDuration => Duration(milliseconds: timeTenths * 100);
  Duration get restDuration => Duration(milliseconds: restTimeTenths * 100);

  factory Concept2Interval.fromJson(
    Map<String, Object?> json,
    int sequenceIndex,
    String fallbackKind,
  ) =>
      Concept2Interval(
        sequenceIndex: sequenceIndex,
        kind: json['type'] as String? ?? fallbackKind,
        timeTenths: (json['time'] as num?)?.round() ?? 0,
        distanceMeters: (json['distance'] as num?)?.round() ?? 0,
        restTimeTenths: (json['rest_time'] as num?)?.round() ?? 0,
        restDistanceMeters: (json['rest_distance'] as num?)?.round() ?? 0,
        strokeRate: (json['stroke_rate'] as num?)?.round(),
        calories: (json['calories_total'] as num?)?.round(),
      );
}

final class Concept2Stroke {
  const Concept2Stroke({
    required this.sequenceIndex,
    required this.timeTenths,
    required this.cumulativeWorkTenths,
    required this.distanceDecimeters,
    this.paceTenths,
    this.strokeRate,
    this.heartRate,
  });

  final int sequenceIndex;
  final int timeTenths;
  final int cumulativeWorkTenths;
  final int distanceDecimeters;
  final int? paceTenths;
  final int? strokeRate;
  final int? heartRate;

  Duration get elapsedWork =>
      Duration(milliseconds: cumulativeWorkTenths * 100);
  double get distanceMeters => distanceDecimeters / 10;

  static List<Concept2Stroke> listFromJson(List<Object?> values) {
    final strokes = <Concept2Stroke>[];
    var previousRawTime = 0;
    var completedWorkTime = 0;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value is! Map) continue;
      final row = value.cast<String, Object?>();
      final rawTime = (row['t'] as num?)?.round() ?? 0;
      if (strokes.isNotEmpty && rawTime < previousRawTime) {
        completedWorkTime += previousRawTime;
      }
      strokes.add(
        Concept2Stroke(
          sequenceIndex: strokes.length,
          timeTenths: rawTime,
          cumulativeWorkTenths: completedWorkTime + rawTime,
          distanceDecimeters: (row['d'] as num?)?.round() ?? 0,
          paceTenths: (row['p'] as num?)?.round(),
          strokeRate: (row['spm'] as num?)?.round(),
          heartRate: (row['hr'] as num?)?.round(),
        ),
      );
      previousRawTime = rawTime;
    }
    return strokes;
  }
}

final class Concept2Result {
  const Concept2Result({
    required this.id,
    required this.machine,
    required this.endedAt,
    required this.distanceMeters,
    required this.workTimeTenths,
    required this.workoutType,
    required this.intervals,
    this.strokes = const [],
    this.restTimeTenths = 0,
    this.strokeRate,
    this.strokeCount,
    this.dragFactor,
    this.calories,
    this.source,
    this.importedAt,
  });

  final int id;
  final Concept2Machine machine;
  final DateTime endedAt;
  final int distanceMeters;
  final int workTimeTenths;
  final int restTimeTenths;
  final String workoutType;
  final int? strokeRate;
  final int? strokeCount;
  final int? dragFactor;
  final int? calories;
  final String? source;
  final DateTime? importedAt;
  final List<Concept2Interval> intervals;
  final List<Concept2Stroke> strokes;

  Duration get workDuration => Duration(milliseconds: workTimeTenths * 100);
  Duration get restDuration => Duration(milliseconds: restTimeTenths * 100);
  Duration get totalDuration => workDuration + restDuration;
  DateTime get startedAt => endedAt.subtract(totalDuration);

  factory Concept2Result.fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    final machine = switch (type) {
      'rower' => Concept2Machine.rower,
      'skierg' => Concept2Machine.skierg,
      _ => throw FormatException('不支持的 Concept2 器械类型：$type'),
    };
    final dateValue = json['date_utc'] ?? json['date'];
    if (dateValue is! String) {
      throw const FormatException('Concept2 记录缺少结束时间');
    }
    var endedAt = DateTime.parse(dateValue.replaceFirst(' ', 'T'));
    if (json['date_utc'] != null && !endedAt.isUtc) {
      endedAt = DateTime.utc(
        endedAt.year,
        endedAt.month,
        endedAt.day,
        endedAt.hour,
        endedAt.minute,
        endedAt.second,
      );
    }
    final workout = json['workout'];
    final intervalValues = <Object?>[];
    var fallbackKind = 'interval';
    if (workout is Map) {
      final normalized = workout.cast<String, Object?>();
      final intervals = normalized['intervals'];
      final splits = normalized['splits'];
      if (intervals is List) {
        intervalValues.addAll(intervals);
      } else if (splits is List) {
        intervalValues.addAll(splits);
        fallbackKind = 'split';
      }
    }
    return Concept2Result(
      id: (json['id'] as num).round(),
      machine: machine,
      endedAt: endedAt.toUtc(),
      distanceMeters: (json['distance'] as num?)?.round() ?? 0,
      workTimeTenths: (json['time'] as num?)?.round() ?? 0,
      restTimeTenths: (json['rest_time'] as num?)?.round() ?? 0,
      workoutType: json['workout_type'] as String? ?? 'unknown',
      strokeRate: (json['stroke_rate'] as num?)?.round(),
      strokeCount: (json['stroke_count'] as num?)?.round(),
      dragFactor: (json['drag_factor'] as num?)?.round(),
      calories: (json['calories_total'] as num?)?.round(),
      source: json['source'] as String?,
      intervals: [
        for (var index = 0; index < intervalValues.length; index++)
          if (intervalValues[index] is Map)
            Concept2Interval.fromJson(
              (intervalValues[index] as Map).cast<String, Object?>(),
              index,
              fallbackKind,
            ),
      ],
      strokes: const [],
    );
  }

  Concept2Result copyWithImportedAt(DateTime value) => Concept2Result(
        id: id,
        machine: machine,
        endedAt: endedAt,
        distanceMeters: distanceMeters,
        workTimeTenths: workTimeTenths,
        restTimeTenths: restTimeTenths,
        workoutType: workoutType,
        strokeRate: strokeRate,
        strokeCount: strokeCount,
        dragFactor: dragFactor,
        calories: calories,
        source: source,
        importedAt: value,
        intervals: intervals,
        strokes: strokes,
      );

  Concept2Result copyWithStrokes(List<Concept2Stroke> value) => Concept2Result(
        id: id,
        machine: machine,
        endedAt: endedAt,
        distanceMeters: distanceMeters,
        workTimeTenths: workTimeTenths,
        restTimeTenths: restTimeTenths,
        workoutType: workoutType,
        strokeRate: strokeRate,
        strokeCount: strokeCount,
        dragFactor: dragFactor,
        calories: calories,
        source: source,
        importedAt: importedAt,
        intervals: intervals,
        strokes: value,
      );
}

abstract final class Concept2ResultMatcher {
  static List<Concept2Result> forSession({
    required Iterable<Concept2Result> results,
    required Concept2Machine machine,
    required DateTime sessionStart,
    required DateTime sessionEnd,
  }) {
    final candidates = results
        .where((result) => result.machine == machine)
        .where(
          (result) =>
              result.endedAt.difference(sessionEnd).abs() <
              const Duration(hours: 3),
        )
        .toList();
    candidates.sort((a, b) {
      final aScore = _score(a, sessionStart, sessionEnd);
      final bScore = _score(b, sessionStart, sessionEnd);
      return aScore.compareTo(bScore);
    });
    return candidates;
  }

  static int _score(
    Concept2Result result,
    DateTime sessionStart,
    DateTime sessionEnd,
  ) {
    final endDifference =
        result.endedAt.difference(sessionEnd).abs().inMilliseconds;
    final localDuration = sessionEnd.difference(sessionStart);
    final durationDifference =
        (result.totalDuration - localDuration).abs().inMilliseconds;
    return endDifference + durationDifference;
  }

  static bool isHighConfidence({
    required Concept2Result result,
    required DateTime sessionStart,
    required DateTime sessionEnd,
  }) {
    final localDuration = sessionEnd.difference(sessionStart);
    final endDifference = result.endedAt.difference(sessionEnd).abs();
    final durationDifference = (result.totalDuration - localDuration).abs();
    final proportionalTolerance = Duration(
      milliseconds: (localDuration.inMilliseconds * .25).round(),
    );
    final durationTolerance = proportionalTolerance > const Duration(minutes: 2)
        ? proportionalTolerance
        : const Duration(minutes: 2);
    return endDifference <= const Duration(minutes: 10) &&
        durationDifference <= durationTolerance;
  }
}
