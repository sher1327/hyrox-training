import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/heart_rate_models.dart';
import 'package:hyrox_training_tracker/features/heart_rate/presentation/controllers/heart_rate_providers.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_models.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_report.dart';
import 'package:hyrox_training_tracker/features/training/presentation/controllers/training_providers.dart';
import 'package:hyrox_training_tracker/features/training/presentation/pages/training_detail_page.dart';

void main() {
  testWidgets('training report shows running lap pace and heart rate',
      (tester) async {
    final start = DateTime.utc(2026, 8, 21, 8);
    final station = StationRecord(
      id: 11,
      sessionId: 1,
      type: StationType.run,
      runNumber: 1,
      sequenceIndex: 0,
      status: SegmentStatus.completed,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 4)),
      duration: const Duration(minutes: 4),
    );
    final lap = RunningLap(
      id: 101,
      sessionId: 1,
      stationRecordId: 11,
      sequenceIndex: 0,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
      duration: const Duration(minutes: 2),
      distanceMeters: 400,
      captureType: RunningLapCaptureType.manual,
    );
    final samples = [
      HeartRateSample(timestamp: start, bpm: 140),
      HeartRateSample(
        timestamp: start.add(const Duration(minutes: 1)),
        bpm: 160,
      ),
    ];
    final session = TrainingSession(
      id: 1,
      mode: TrainingMode.single,
      title: '跑步训练',
      status: TrainingStatus.completed,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 4)),
      totalDuration: const Duration(minutes: 4),
      avgHeartRate: 150,
      maxHeartRate: 160,
      heartRateSampleCount: 2,
    );
    final report = TrainingReport.build(session, [station], [lap]);
    final analysis = HeartRateAnalysis.build(samples, [station], [lap]);

    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingReportProvider.overrideWith((ref, id) async => report),
          heartRateAnalysisProvider.overrideWith((ref, id) async => analysis),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const TrainingDetailPage(sessionId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('跑步手动分段'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );

    expect(find.text('跑步手动分段'), findsOneWidget);
    expect(find.text('400 m'), findsOneWidget);
    expect(find.text('5:00 /km'), findsOneWidget);
    expect(find.text('平均 150 · 最高 160 bpm'), findsWidgets);
  });
}
