import 'training_models.dart';

final class TrainingReport {
  const TrainingReport({
    required this.session,
    required this.stations,
    required this.totalDuration,
    required this.runningDuration,
    required this.stationDuration,
    required this.transitionDuration,
    required this.completedSegments,
  });

  factory TrainingReport.build(
    TrainingSession session,
    List<StationRecord> stations,
  ) {
    final running = _sum(
      stations.where((station) => station.type == StationType.run),
    );
    final functional = _sum(
      stations.where((station) => station.type != StationType.run),
    );
    final measured = running + functional;
    final total = session.totalDuration ?? measured;
    final hasRecordedTransitions = stations.any(
      (station) => station.transitionStartedAt != null,
    );
    final recordedTransition = stations.fold(
      Duration.zero,
      (sum, station) => sum + (station.transitionDuration ?? Duration.zero),
    );
    final transition = hasRecordedTransitions
        ? recordedTransition
        : total > measured
            ? total - measured
            : Duration.zero;

    return TrainingReport(
      session: session,
      stations: List.unmodifiable(stations),
      totalDuration: total,
      runningDuration: running,
      stationDuration: functional,
      transitionDuration: transition,
      completedSegments: stations
          .where((station) => station.status == SegmentStatus.completed)
          .length,
    );
  }

  final TrainingSession session;
  final List<StationRecord> stations;
  final Duration totalDuration;
  final Duration runningDuration;
  final Duration stationDuration;
  final Duration transitionDuration;
  final int completedSegments;

  List<StationRecord> get slowestFunctionalStations {
    final result = stations
        .where(
          (station) =>
              station.type != StationType.run && station.duration != null,
        )
        .toList()
      ..sort((a, b) => b.duration!.compareTo(a.duration!));
    return result.take(5).toList(growable: false);
  }
}

Duration _sum(Iterable<StationRecord> stations) => stations.fold(
      Duration.zero,
      (sum, station) => sum + (station.duration ?? Duration.zero),
    );
