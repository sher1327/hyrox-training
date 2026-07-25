final class IntervalsCredentials {
  const IntervalsCredentials({
    required this.athleteId,
    required this.apiKey,
  });

  final String athleteId;
  final String apiKey;
}

final class IntervalsActivity {
  const IntervalsActivity({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.elapsedTime,
    required this.hasHeartRate,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final Duration elapsedTime;
  final bool hasHeartRate;

  DateTime get endedAt => startedAt.add(elapsedTime);

  factory IntervalsActivity.fromJson(Map<String, Object?> json) {
    final startValue = json['start_date'] ?? json['start_date_local'];
    if (startValue is! String) {
      throw const FormatException('Intervals.icu 活动缺少开始时间');
    }
    final seconds = (json['elapsed_time'] as num?)?.round() ?? 0;
    return IntervalsActivity(
      id: json['id']! as String,
      name: (json['name'] as String?) ?? '未命名活动',
      startedAt: DateTime.parse(startValue),
      elapsedTime: Duration(seconds: seconds),
      hasHeartRate: json['has_heartrate'] == true,
    );
  }
}

abstract final class IntervalsActivityMatcher {
  static List<IntervalsActivity> overlappingSession({
    required Iterable<IntervalsActivity> activities,
    required DateTime sessionStart,
    required DateTime sessionEnd,
  }) {
    return activities
        .where(
          (activity) =>
              activity.hasHeartRate &&
              activity.startedAt.isBefore(sessionEnd) &&
              activity.endedAt.isAfter(sessionStart),
        )
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }
}
