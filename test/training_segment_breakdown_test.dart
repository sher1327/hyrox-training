import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/heart_rate_models.dart';
import 'package:hyrox_training_tracker/features/heart_rate/presentation/controllers/heart_rate_providers.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_models.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_report.dart';
import 'package:hyrox_training_tracker/features/training/presentation/controllers/training_providers.dart';
import 'package:hyrox_training_tracker/features/training/presentation/pages/training_detail_page.dart';
import 'package:hyrox_training_tracker/features/training/presentation/pages/training_segment_breakdown_page.dart';

void main() {
  testWidgets('running breakdown lists each run and pace', (tester) async {
    final fixture = _fixture();
    await _pumpBreakdown(
      tester,
      fixture: fixture,
      kind: TrainingBreakdownKind.running,
    );

    expect(find.text('跑步分段'), findsOneWidget);
    expect(find.text('每段跑步时间'), findsOneWidget);
    expect(find.textContaining('RUN 1'), findsOneWidget);
    expect(find.textContaining('RUN 2'), findsOneWidget);
    expect(find.textContaining('SKI ERG'), findsNothing);
    expect(find.text('5:00 /km'), findsOneWidget);
    expect(find.text('6:00 /km'), findsOneWidget);
    expect(find.text('00:11:00'), findsOneWidget);
  });

  testWidgets('station breakdown lists each functional station',
      (tester) async {
    final fixture = _fixture();
    await _pumpBreakdown(
      tester,
      fixture: fixture,
      kind: TrainingBreakdownKind.station,
    );

    expect(find.text('站点分段'), findsOneWidget);
    expect(find.text('每段站点时间'), findsOneWidget);
    expect(find.textContaining('SKI ERG'), findsOneWidget);
    expect(find.textContaining('WALL BALL'), findsOneWidget);
    expect(find.textContaining('RUN 1'), findsNothing);
    expect(find.text('00:05:00'), findsOneWidget);
  });

  testWidgets('report running metric opens running breakdown', (tester) async {
    final fixture = _fixture();
    final router = GoRouter(
      initialLocation: '/training/42',
      routes: [
        GoRoute(
          path: '/training/:id',
          builder: (_, __) => const TrainingDetailPage(sessionId: 42),
        ),
        GoRoute(
          path: '/training/:id/breakdown/:kind',
          builder: (_, state) => TrainingSegmentBreakdownPage(
            sessionId: 42,
            kind: state.pathParameters['kind'] == 'stations'
                ? TrainingBreakdownKind.station
                : TrainingBreakdownKind.running,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(fixture),
        child: MaterialApp.router(
          theme: ThemeData.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('跑步时间'));
    await tester.pumpAndSettle();

    expect(find.text('跑步分段'), findsOneWidget);
    expect(find.textContaining('RUN 1'), findsOneWidget);
    expect(find.textContaining('SKI ERG'), findsNothing);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('站点时间'));
    await tester.pumpAndSettle();

    expect(find.text('站点分段'), findsOneWidget);
    expect(find.textContaining('SKI ERG'), findsOneWidget);
    expect(find.textContaining('RUN 1'), findsNothing);
  });
}

Future<void> _pumpBreakdown(
  WidgetTester tester, {
  required _Fixture fixture,
  required TrainingBreakdownKind kind,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(fixture),
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: TrainingSegmentBreakdownPage(sessionId: 42, kind: kind),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Override> _overrides(_Fixture fixture) => [
      trainingReportProvider.overrideWith(
        (ref, sessionId) async => fixture.report,
      ),
      heartRateAnalysisProvider.overrideWith(
        (ref, sessionId) async => fixture.heartRate,
      ),
    ];

_Fixture _fixture() {
  final start = DateTime.utc(2026, 7, 26, 1);
  final session = TrainingSession(
    id: 42,
    mode: TrainingMode.single,
    title: 'HYROX 女子大众（Open）',
    status: TrainingStatus.completed,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 16)),
    totalDuration: const Duration(minutes: 16),
    avgHeartRate: 150,
    maxHeartRate: 180,
    heartRateSampleCount: 4,
  );
  final stations = [
    StationRecord(
      id: 1,
      sessionId: 42,
      type: StationType.run,
      runNumber: 1,
      sequenceIndex: 0,
      status: SegmentStatus.completed,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 5)),
      duration: const Duration(minutes: 5),
      targetDistanceMeters: 1000,
    ),
    StationRecord(
      id: 2,
      sessionId: 42,
      type: StationType.skiErg,
      sequenceIndex: 1,
      status: SegmentStatus.completed,
      startedAt: start.add(const Duration(minutes: 5)),
      endedAt: start.add(const Duration(minutes: 8)),
      duration: const Duration(minutes: 3),
      targetDistanceMeters: 1000,
    ),
    StationRecord(
      id: 3,
      sessionId: 42,
      type: StationType.run,
      runNumber: 2,
      sequenceIndex: 2,
      status: SegmentStatus.completed,
      startedAt: start.add(const Duration(minutes: 8)),
      endedAt: start.add(const Duration(minutes: 14)),
      duration: const Duration(minutes: 6),
      targetDistanceMeters: 1000,
    ),
    StationRecord(
      id: 4,
      sessionId: 42,
      type: StationType.wallBall,
      sequenceIndex: 3,
      status: SegmentStatus.completed,
      startedAt: start.add(const Duration(minutes: 14)),
      endedAt: start.add(const Duration(minutes: 16)),
      duration: const Duration(minutes: 2),
      targetWeightKg: 4,
      targetRepetitions: 100,
    ),
  ];
  final samples = [
    HeartRateSample(timestamp: start, bpm: 120),
    HeartRateSample(
      timestamp: start.add(const Duration(minutes: 6)),
      bpm: 150,
    ),
    HeartRateSample(
      timestamp: start.add(const Duration(minutes: 10)),
      bpm: 160,
    ),
    HeartRateSample(
      timestamp: start.add(const Duration(minutes: 15)),
      bpm: 180,
    ),
  ];
  return _Fixture(
    report: TrainingReport.build(session, stations),
    heartRate: HeartRateAnalysis.build(samples, stations),
  );
}

final class _Fixture {
  const _Fixture({required this.report, required this.heartRate});

  final TrainingReport report;
  final HeartRateAnalysis heartRate;
}
