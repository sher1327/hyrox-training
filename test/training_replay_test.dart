import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/heart_rate_models.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/services/heart_rate_time_series_mapper.dart';
import 'package:hyrox_training_tracker/features/replay/domain/models/training_replay.dart';
import 'package:hyrox_training_tracker/features/replay/presentation/controllers/training_replay_providers.dart';
import 'package:hyrox_training_tracker/features/replay/presentation/pages/training_replay_page.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_models.dart';

void main() {
  test('relative time and heart-rate arrays become sorted absolute samples',
      () {
    final start = DateTime.utc(2026, 7, 23, 0, 21, 19);
    final samples = HeartRateTimeSeriesMapper.fromRelativeStreams(
      startedAt: start,
      times: const [10, 0, 5, -1, 15],
      heartRates: const [140, 100, 0, 160],
      source: HeartRateSources.intervalsIcu,
    );

    expect(samples, hasLength(2));
    expect(samples.map((sample) => sample.bpm), [100, 140]);
    expect(samples.first.timestamp, start);
    expect(samples.last.timestamp, start.add(const Duration(seconds: 10)));
    expect(samples.last.source, HeartRateSources.intervalsIcu);
  });

  test('replay builds interpolated heart rate, segments and five zones', () {
    final start = DateTime.utc(2026, 7, 23, 0, 21, 19);
    final replay = TrainingReplay.build(
      session: TrainingSession(
        id: 9,
        mode: TrainingMode.single,
        title: 'Replay test',
        status: TrainingStatus.completed,
        startedAt: start,
        endedAt: start.add(const Duration(seconds: 50)),
        totalDuration: const Duration(seconds: 50),
      ),
      stations: [
        StationRecord(
          id: 1,
          sessionId: 9,
          type: StationType.run,
          sequenceIndex: 0,
          status: SegmentStatus.completed,
          startedAt: start,
          endedAt: start.add(const Duration(seconds: 20)),
        ),
      ],
      samples: [
        for (final value in const [
          (seconds: 0, bpm: 100),
          (seconds: 10, bpm: 130),
          (seconds: 20, bpm: 150),
          (seconds: 30, bpm: 170),
          (seconds: 40, bpm: 190),
        ])
          HeartRateSample(
            timestamp: start.add(Duration(seconds: value.seconds)),
            bpm: value.bpm,
          ),
      ],
      zoneReferenceMaximumBpm: 200,
    );

    expect(replay.averageHeartRate, 148);
    expect(replay.maximumHeartRate, 190);
    expect(replay.heartRateAt(const Duration(seconds: 5)), 115);
    expect(replay.segmentAt(const Duration(seconds: 19))?.stationId, 1);
    expect(replay.segmentAt(const Duration(seconds: 20)), isNull);
    expect(
      replay.zoneStats.map((stat) => stat.duration),
      everyElement(const Duration(seconds: 10)),
    );
    expect(
      replay.zoneStats.map((stat) => stat.percentage),
      everyElement(closeTo(.2, .0001)),
    );
    expect(replay.segments.single.averageHeartRate, 115);

    final payload = replay.toAnalysisPayload(maxSamples: 2);
    expect(payload['schema_version'], 1);
    expect(
      ((payload['heart_rate'] as Map<String, Object?>)['samples'] as List),
      hasLength(2),
    );
  });

  test('zone duration does not fill a long sensor gap', () {
    final start = DateTime.utc(2026, 7, 23);
    final replay = TrainingReplay.build(
      session: TrainingSession(
        id: 1,
        mode: TrainingMode.single,
        title: 'Gap test',
        status: TrainingStatus.completed,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 10)),
      ),
      stations: const [],
      samples: [
        HeartRateSample(timestamp: start, bpm: 100),
        HeartRateSample(
          timestamp: start.add(const Duration(minutes: 9)),
          bpm: 180,
        ),
      ],
      zoneReferenceMaximumBpm: 200,
    );

    final covered = replay.zoneStats.fold(
      Duration.zero,
      (sum, stat) => sum + stat.duration,
    );
    expect(covered, lessThan(const Duration(minutes: 2)));
    expect(replay.heartRateAt(const Duration(minutes: 5)), isNull);
  });

  test('playback controller supports seek, skip and speed', () {
    final controller = TrainingReplayController(
      duration: const Duration(minutes: 1),
    );
    addTearDown(controller.dispose);

    controller.seek(const Duration(seconds: 20));
    controller.skip(const Duration(seconds: 15));
    controller.setSpeed(2);

    expect(controller.state.elapsed, const Duration(seconds: 35));
    expect(controller.state.speed, 2);
    controller.skip(const Duration(minutes: 2));
    expect(controller.state.elapsed, const Duration(minutes: 1));
  });

  testWidgets('replay page renders chart, zones and playback controls',
      (tester) async {
    final replay = _replayFixture();
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingReplayProvider.overrideWith(
            (ref, sessionId) async => replay,
          ),
        ],
        child: MaterialApp(
          themeMode: ThemeMode.dark,
          darkTheme: ThemeData.dark(),
          home: const TrainingReplayPage(sessionId: 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('训练回放'), findsOneWidget);
    expect(find.text('心率曲线'), findsOneWidget);
    expect(find.text('心率 Zone'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
  });
}

TrainingReplay _replayFixture() {
  final start = DateTime.utc(2026, 7, 23, 0, 21, 19);
  return TrainingReplay.build(
    session: TrainingSession(
      id: 9,
      mode: TrainingMode.single,
      title: 'HYROX 模拟训练',
      status: TrainingStatus.completed,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
      totalDuration: const Duration(minutes: 2),
    ),
    stations: [
      StationRecord(
        id: 1,
        sessionId: 9,
        type: StationType.run,
        sequenceIndex: 0,
        status: SegmentStatus.completed,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 1)),
      ),
      StationRecord(
        id: 2,
        sessionId: 9,
        type: StationType.skiErg,
        sequenceIndex: 1,
        status: SegmentStatus.completed,
        startedAt: start.add(const Duration(minutes: 1)),
        endedAt: start.add(const Duration(minutes: 2)),
      ),
    ],
    samples: [
      for (var seconds = 0; seconds <= 120; seconds += 5)
        HeartRateSample(
          timestamp: start.add(Duration(seconds: seconds)),
          bpm: 100 + (seconds / 2).round(),
        ),
    ],
    zoneReferenceMaximumBpm: 190,
  );
}
