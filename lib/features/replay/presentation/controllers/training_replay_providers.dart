import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../heart_rate/presentation/controllers/heart_rate_providers.dart';
import '../../../training/presentation/controllers/training_providers.dart';
import '../../domain/models/training_replay.dart';

final trainingReplayProvider = FutureProvider.autoDispose
    .family<TrainingReplay?, int>((ref, sessionId) async {
  final trainingRepository =
      await ref.watch(trainingRepositoryFutureProvider.future);
  final heartRateRepository =
      await ref.watch(heartRateRepositoryFutureProvider.future);
  final session = await trainingRepository.getSession(sessionId);
  if (session == null) return null;
  final stationsFuture = trainingRepository.listStations(sessionId);
  final samplesFuture = heartRateRepository.listSamples(sessionId);
  final stations = await stationsFuture;
  final samples = await samplesFuture;
  return TrainingReplay.build(
    session: session,
    stations: stations,
    samples: samples,
  );
});

final class ReplayPlaybackKey {
  const ReplayPlaybackKey({required this.sessionId, required this.duration});

  final int sessionId;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is ReplayPlaybackKey &&
      other.sessionId == sessionId &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(sessionId, duration);
}

final class ReplayPlaybackState {
  const ReplayPlaybackState({
    required this.elapsed,
    required this.isPlaying,
    required this.speed,
  });

  const ReplayPlaybackState.initial()
      : elapsed = Duration.zero,
        isPlaying = false,
        speed = 1;

  final Duration elapsed;
  final bool isPlaying;
  final double speed;

  ReplayPlaybackState copyWith({
    Duration? elapsed,
    bool? isPlaying,
    double? speed,
  }) =>
      ReplayPlaybackState(
        elapsed: elapsed ?? this.elapsed,
        isPlaying: isPlaying ?? this.isPlaying,
        speed: speed ?? this.speed,
      );
}

final replayPlaybackProvider = StateNotifierProvider.autoDispose
    .family<TrainingReplayController, ReplayPlaybackState, ReplayPlaybackKey>(
  (ref, key) => TrainingReplayController(duration: key.duration),
);

final class TrainingReplayController
    extends StateNotifier<ReplayPlaybackState> {
  TrainingReplayController({required this.duration})
      : super(const ReplayPlaybackState.initial());

  final Duration duration;
  Timer? _timer;
  DateTime? _anchorTime;
  Duration _anchorElapsed = Duration.zero;

  void toggle() => state.isPlaying ? pause() : play();

  void play() {
    if (duration <= Duration.zero || state.isPlaying) return;
    if (state.elapsed >= duration) {
      state = state.copyWith(elapsed: Duration.zero);
    }
    _anchorElapsed = state.elapsed;
    _anchorTime = DateTime.now();
    state = state.copyWith(isPlaying: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void pause() {
    if (!state.isPlaying) return;
    _synchronize();
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(isPlaying: false);
  }

  void seek(Duration value) {
    final clamped = _clamp(value);
    state = state.copyWith(elapsed: clamped);
    _anchorElapsed = clamped;
    _anchorTime = DateTime.now();
  }

  void skip(Duration delta) => seek(state.elapsed + delta);

  void setSpeed(double speed) {
    if (speed <= 0 || speed == state.speed) return;
    if (state.isPlaying) _synchronize();
    state = state.copyWith(speed: speed);
    _anchorElapsed = state.elapsed;
    _anchorTime = DateTime.now();
  }

  void _tick() {
    _synchronize();
    if (state.elapsed >= duration) {
      _timer?.cancel();
      _timer = null;
      state = state.copyWith(isPlaying: false, elapsed: duration);
    }
  }

  void _synchronize() {
    if (!state.isPlaying || _anchorTime == null) return;
    final wallElapsed = DateTime.now().difference(_anchorTime!);
    final scaled = Duration(
      microseconds: (wallElapsed.inMicroseconds * state.speed).round(),
    );
    state = state.copyWith(elapsed: _clamp(_anchorElapsed + scaled));
  }

  Duration _clamp(Duration value) {
    if (value < Duration.zero) return Duration.zero;
    if (value > duration) return duration;
    return value;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
