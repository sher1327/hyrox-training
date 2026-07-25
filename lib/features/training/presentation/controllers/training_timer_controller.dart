import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/time/clock.dart';
import '../../domain/models/training_models.dart';
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
  });

  final TrainingSession session;
  final List<StationRecord> stations;
  final DateTime now;
  final String selectedAthleteName;
  final bool isSaving;

  StationRecord? get current =>
      stations.where((item) => item.status == SegmentStatus.active).firstOrNull;

  StationRecord? get transitionSource =>
      stations.where((item) => item.isTransitionActive).firstOrNull;

  StationRecord? get nextAfterTransition {
    final source = transitionSource;
    if (source == null) return null;
    return stations
        .where((item) => item.sequenceIndex == source.sequenceIndex + 1)
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

  TrainingTimerState copyWith({
    List<StationRecord>? stations,
    DateTime? now,
    String? selectedAthleteName,
    bool? isSaving,
  }) =>
      TrainingTimerState(
        session: session,
        stations: stations ?? this.stations,
        now: now ?? this.now,
        selectedAthleteName: selectedAthleteName ?? this.selectedAthleteName,
        isSaving: isSaving ?? this.isSaving,
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
    final stations = await _repository.listStations(arg);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return TrainingTimerState(
      session: session,
      stations: stations,
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
      state = AsyncData(
        value.copyWith(
          stations: refreshed,
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
    final nextIndex = current.sequenceIndex + 1;
    final completed = nextIndex >= value.stations.length;
    final nextStationId = completed ? null : value.stations[nextIndex].id;
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
      );
      if (completed) {
        _ticker?.cancel();
        ref.invalidate(trainingSessionsProvider);
        ref.invalidate(trainingReportProvider(value.session.id));
      }

      final refreshed = await _repository.listStations(value.session.id);
      state = AsyncData(
        value.copyWith(
          stations: refreshed,
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
}
