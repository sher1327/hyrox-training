import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/time/clock.dart';
import '../../domain/models/training_models.dart';
import '../../domain/models/training_template.dart';
import '../../domain/repositories/training_repository.dart';
import 'training_providers.dart';

final trainingTimerProvider = AsyncNotifierProvider.autoDispose
    .family<TrainingTimerController, TrainingTimerState, int>(
  TrainingTimerController.new,
);

final class TrainingTimerState {
  const TrainingTimerState({
    required this.session,
    required this.stations,
    required this.now,
    this.selectedAthleteName = '我',
    this.isSaving = false,
    this.runningLaps = const [],
  });

  final TrainingSession session;
  final List<StationRecord> stations;
  final DateTime now;
  final String selectedAthleteName;
  final bool isSaving;
  final List<RunningLap> runningLaps;

  StationRecord? get current =>
      stations.where((item) => item.status == SegmentStatus.active).firstOrNull;

  StationRecord? get transitionSource =>
      stations.where((item) => item.isTransitionActive).firstOrNull;

  List<StationRecord> get pendingStations => stations
      .where((item) => item.status == SegmentStatus.pending)
      .toList(growable: false);

  List<StationRecord> get removedStations => stations
      .where((item) => item.wasRemovedBeforeStart)
      .toList(growable: false);

  StationRecord? get nextPending => pendingStations.firstOrNull;

  List<StationRecord> get executableStations => stations
      .where((item) => !item.wasRemovedBeforeStart)
      .toList(growable: false);

  int get currentOrdinal {
    final active = current;
    if (active == null) return 0;
    return executableStations.indexWhere((item) => item.id == active.id) + 1;
  }

  StationRecord? get nextAfterTransition {
    final source = transitionSource;
    if (source == null) return null;
    return nextPending;
  }

  /// Only the station immediately before the current flow position can be
  /// restored. This prevents an undo from crossing confirmed later records.
  StationRecord? get undoCandidate {
    final transition = transitionSource;
    if (transition != null) return transition;
    final active = current;
    if (active == null || active.sequenceIndex == 0) return null;
    return stations
        .where(
          (item) =>
              item.sequenceIndex == active.sequenceIndex - 1 &&
              (item.status == SegmentStatus.completed ||
                  item.status == SegmentStatus.skipped),
        )
        .firstOrNull;
  }

  bool get isTransitioning => transitionSource != null;

  bool get hasActiveTimer => current != null || isTransitioning;

  Duration get totalElapsed => session.startedAt == null
      ? Duration.zero
      : now.difference(session.startedAt!);

  Duration get segmentElapsed {
    final start = current?.startedAt;
    return start == null ? Duration.zero : now.difference(start);
  }

  Duration get transitionElapsed {
    final start = transitionSource?.transitionStartedAt;
    return start == null ? Duration.zero : now.difference(start);
  }

  List<RunningLap> get currentRunningLaps {
    final stationId = current?.id;
    if (stationId == null) return const [];
    return runningLaps
        .where((lap) => lap.stationRecordId == stationId)
        .toList(growable: false);
  }

  Duration get currentLapElapsed {
    final active = current;
    if (active == null || active.type != StationType.run) return Duration.zero;
    final start = currentRunningLaps.lastOrNull?.endedAt ?? active.startedAt;
    return start == null ? Duration.zero : now.difference(start);
  }

  TrainingTimerState copyWith({
    List<StationRecord>? stations,
    DateTime? now,
    String? selectedAthleteName,
    bool? isSaving,
    List<RunningLap>? runningLaps,
  }) =>
      TrainingTimerState(
        session: session,
        stations: stations ?? this.stations,
        now: now ?? this.now,
        selectedAthleteName: selectedAthleteName ?? this.selectedAthleteName,
        isSaving: isSaving ?? this.isSaving,
        runningLaps: runningLaps ?? this.runningLaps,
      );
}

final class TrainingTimerController
    extends AutoDisposeFamilyAsyncNotifier<TrainingTimerState, int> {
  Timer? _ticker;
  late TrainingRepository _repository;
  late Clock _clock;

  @override
  Future<TrainingTimerState> build(int arg) async {
    _repository = await ref.watch(trainingRepositoryFutureProvider.future);
    _clock = ref.watch(clockProvider);
    ref.onDispose(() => _ticker?.cancel());
    final session = await _repository.getSession(arg);
    if (session == null) throw StateError('Training session $arg not found');
    final values = await Future.wait([
      _repository.listStations(arg),
      _repository.listRunningLaps(arg),
    ]);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return TrainingTimerState(
      session: session,
      stations: values[0] as List<StationRecord>,
      runningLaps: values[1] as List<RunningLap>,
      now: _clock.now(),
    );
  }

  void _tick() {
    final value = state.valueOrNull;
    if (value != null) state = AsyncData(value.copyWith(now: _clock.now()));
  }

  /// Recalculates elapsed durations from persisted UTC timestamps after the
  /// application returns from background or the device is unlocked.
  void syncAfterResume() {
    final value = state.valueOrNull;
    if (value != null) {
      state = AsyncData(value.copyWith(now: _clock.now()));
    }
  }

  void selectAthlete(String athleteName) {
    final value = state.requireValue;
    state = AsyncData(value.copyWith(selectedAthleteName: athleteName));
  }

  Future<RunningLap?> recordRunningLap() async {
    final value = state.requireValue;
    final current = value.current;
    if (current == null || current.type != StationType.run || value.isSaving) {
      return null;
    }
    state = AsyncData(value.copyWith(isSaving: true));
    final now = _clock.now();
    try {
      final lapId = await _repository.recordRunningLap(
        sessionId: value.session.id,
        stationId: current.id,
        endedAt: now,
      );
      final laps = await _repository.listRunningLaps(value.session.id);
      state = AsyncData(
        value.copyWith(
          runningLaps: laps,
          now: now,
          isSaving: false,
        ),
      );
      return laps.where((lap) => lap.id == lapId).firstOrNull;
    } catch (_) {
      state = AsyncData(value.copyWith(now: now, isSaving: false));
      rethrow;
    }
  }

  Future<void> updateRunningLapDistance(
    int lapId,
    int? distanceMeters,
  ) async {
    final value = state.requireValue;
    if (value.isSaving) return;
    state = AsyncData(value.copyWith(isSaving: true));
    try {
      await _repository.updateRunningLapDistance(
        lapId: lapId,
        distanceMeters: distanceMeters,
      );
      final laps = await _repository.listRunningLaps(value.session.id);
      state = AsyncData(
        value.copyWith(
          runningLaps: laps,
          now: _clock.now(),
          isSaving: false,
        ),
      );
    } catch (_) {
      state = AsyncData(value.copyWith(isSaving: false));
      rethrow;
    }
  }

  Future<bool> completeCurrent({required bool startTransition}) async =>
      _advance(skip: false, startTransition: startTransition);

  Future<bool> skipCurrent({required bool startTransition}) async =>
      _advance(skip: true, startTransition: startTransition);

  Future<void> startNextAfterTransition() async {
    final value = state.requireValue;
    final source = value.transitionSource;
    final next = value.nextAfterTransition;
    if (source == null || next == null || value.isSaving) return;
    state = AsyncData(value.copyWith(isSaving: true));
    final now = _clock.now();
    try {
      await _repository.finishTransitionAndActivateNext(
        fromStationId: source.id,
        nextStationId: next.id,
        at: now,
      );
      final refreshed = await _repository.listStations(value.session.id);
      final laps = await _repository.listRunningLaps(value.session.id);
      state = AsyncData(
        value.copyWith(
          stations: refreshed,
          runningLaps: laps,
          now: now,
          isSaving: false,
        ),
      );
    } catch (_) {
      state = AsyncData(value.copyWith(now: now, isSaving: false));
      rethrow;
    }
  }

  /// Completes a transition when every remaining project was removed from the
  /// queue while the transition timer was running.
  Future<bool> finishAfterTransition() async {
    final value = state.requireValue;
    final source = value.transitionSource;
    if (source == null || value.nextPending != null || value.isSaving) {
      return false;
    }
    state = AsyncData(value.copyWith(isSaving: true));
    final now = _clock.now();
    try {
      await _repository.finishTransitionAndCompleteSession(
        sessionId: value.session.id,
        fromStationId: source.id,
        at: now,
      );
      _ticker?.cancel();
      ref.invalidate(trainingSessionsProvider);
      ref.invalidate(trainingReportProvider(value.session.id));
      final refreshed = await _repository.listStations(value.session.id);
      state = AsyncData(
        value.copyWith(stations: refreshed, now: now, isSaving: false),
      );
      return true;
    } catch (_) {
      state = AsyncData(value.copyWith(now: now, isSaving: false));
      rethrow;
    }
  }

  Future<void> reorderPendingStations(List<int> orderedStationIds) async {
    await _updateQueue(
      (value, now) => _repository.reorderPendingStations(
        sessionId: value.session.id,
        orderedStationIds: orderedStationIds,
        changedAt: now,
      ),
    );
  }

  Future<int?> addPendingStation(
    TemplateSegmentInput segment, {
    required bool insertAsNext,
  }) async {
    int? stationId;
    await _updateQueue((value, now) async {
      stationId = await _repository.addPendingStation(
        sessionId: value.session.id,
        segment: segment,
        insertAsNext: insertAsNext,
        changedAt: now,
      );
    });
    return stationId;
  }

  Future<void> skipPendingStation(int stationId, {required String reason}) =>
      _updateQueue(
        (value, now) => _repository.skipPendingStation(
          sessionId: value.session.id,
          stationId: stationId,
          reason: reason,
          changedAt: now,
        ),
      );

  Future<void> restoreSkippedPendingStation(
    int stationId, {
    required int pendingIndex,
  }) =>
      _updateQueue(
        (value, now) => _repository.restoreSkippedPendingStation(
          sessionId: value.session.id,
          stationId: stationId,
          pendingIndex: pendingIndex,
          changedAt: now,
        ),
      );

  Future<void> updateActualPerformance(
    int stationId,
    StationActualPerformance actualPerformance,
  ) async {
    final value = state.requireValue;
    if (value.isSaving) return;
    state = AsyncData(value.copyWith(isSaving: true));
    try {
      await _repository.updateStationActualPerformance(
        stationId: stationId,
        actualPerformance: actualPerformance,
      );
      final refreshed = await _repository.listStations(value.session.id);
      final laps = await _repository.listRunningLaps(value.session.id);
      state = AsyncData(
        value.copyWith(
          stations: refreshed,
          runningLaps: laps,
          now: _clock.now(),
          isSaving: false,
        ),
      );
    } catch (_) {
      state = AsyncData(value.copyWith(isSaving: false));
      rethrow;
    }
  }

  Future<void> undoLastCompletion() async {
    final value = state.requireValue;
    if (value.undoCandidate == null || value.isSaving) return;
    state = AsyncData(value.copyWith(isSaving: true));
    final now = _clock.now();
    try {
      await _repository.undoLastStationCompletion(
        sessionId: value.session.id,
        restoredAt: now,
      );
      final refreshed = await _repository.listStations(value.session.id);
      final laps = await _repository.listRunningLaps(value.session.id);
      state = AsyncData(
        value.copyWith(
          stations: refreshed,
          runningLaps: laps,
          now: now,
          isSaving: false,
        ),
      );
    } catch (_) {
      state = AsyncData(value.copyWith(now: now, isSaving: false));
      rethrow;
    }
  }

  Future<void> cancelTraining() async {
    final value = state.requireValue;
    if (value.isSaving) return;
    state = AsyncData(value.copyWith(isSaving: true));
    final now = _clock.now();
    try {
      await _repository.cancelSession(value.session.id, now);
      _ticker?.cancel();
      ref.invalidate(trainingSessionsProvider);
      ref.invalidate(trainingReportProvider(value.session.id));
    } catch (_) {
      state = AsyncData(value.copyWith(now: now, isSaving: false));
      rethrow;
    }
  }

  Future<void> _updateQueue(
    Future<void> Function(TrainingTimerState value, DateTime now) operation,
  ) async {
    final value = state.requireValue;
    if (value.isSaving) return;
    state = AsyncData(value.copyWith(isSaving: true));
    final now = _clock.now();
    try {
      await operation(value, now);
      final refreshed = await _repository.listStations(value.session.id);
      state = AsyncData(
        value.copyWith(stations: refreshed, now: now, isSaving: false),
      );
    } catch (_) {
      state = AsyncData(value.copyWith(now: now, isSaving: false));
      rethrow;
    }
  }

  /// Returns true when the entire simulation has completed.
  Future<bool> _advance({
    required bool skip,
    required bool startTransition,
  }) async {
    final value = state.requireValue;
    final current = value.current;
    if (current == null || value.isSaving) return false;
    state = AsyncData(value.copyWith(isSaving: true));

    final now = _clock.now();
    final next = value.nextPending;
    final completed = next == null;
    final nextStationId = next?.id;
    try {
      await _repository.finishStationAndAdvance(
        sessionId: value.session.id,
        stationId: current.id,
        nextStationId: nextStationId,
        endedAt: now,
        duration: now.difference(current.startedAt!),
        athleteName: value.selectedAthleteName,
        skipped: skip,
        startTransition: startTransition && !completed,
        actualPerformance: skip
            ? const StationActualPerformance()
            : StationActualPerformance.fromTarget(current),
      );
      if (completed) {
        _ticker?.cancel();
        ref.invalidate(trainingSessionsProvider);
        ref.invalidate(trainingReportProvider(value.session.id));
      }

      final refreshed = await _repository.listStations(value.session.id);
      final laps = await _repository.listRunningLaps(value.session.id);
      state = AsyncData(
        value.copyWith(
          stations: refreshed,
          runningLaps: laps,
          now: now,
          isSaving: false,
        ),
      );
      return completed;
    } catch (_) {
      state = AsyncData(value.copyWith(now: now, isSaving: false));
      rethrow;
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
