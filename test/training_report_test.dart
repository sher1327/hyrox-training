import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_models.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_report.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_template.dart';
import 'package:hyrox_training_tracker/features/training/presentation/controllers/training_timer_controller.dart';
import 'package:hyrox_training_tracker/core/database/database_schema.dart';

void main() {
  test('standard HYROX flow alternates eight runs and eight stations', () {
    expect(standardHyroxFlow, hasLength(16));
    expect(
      standardHyroxFlow.where((segment) => segment.type == StationType.run),
      hasLength(8),
    );
    expect(
      standardHyroxFlow.where((segment) => segment.type != StationType.run),
      hasLength(8),
    );
    for (var index = 0; index < standardHyroxFlow.length; index++) {
      expect(
        standardHyroxFlow[index].type == StationType.run,
        index.isEven,
      );
    }
  });

  test('built-in templates contain official open and men pro specifications',
      () {
    final templates = DatabaseSchema.builtInTemplates;
    expect(templates.map((item) => item.name), [
      'HYROX 男子大众（Open）',
      'HYROX 女子大众（Open）',
      'HYROX 男子精英（Pro）',
    ]);
    expect(templates.every((item) => item.segments.length == 16), isTrue);
    expect(templates[0].segments[3].weightKg, 152);
    expect(templates[1].segments[3].weightKg, 102);
    expect(templates[2].segments[3].weightKg, 202);
    expect(templates[2].segments[15].weightKg, 9);
    expect(templates[2].segments[15].repetitions, 100);
    expect(templates.every((item) => item.segments[1].resistanceLevel == 6),
        isTrue);
    expect(templates.every((item) => item.segments[9].resistanceLevel == 6),
        isTrue);
  });

  test('optional station specifications produce a readable label', () {
    const segment = TemplateSegmentInput(
      type: StationType.farmerCarry,
      targetDistanceMeters: 200,
      targetWeightKg: 24,
    );
    expect(segment.displayName, 'FARMER CARRY · 2 × 24 kg · 200 m');
  });

  test('report separates running, functional and transition durations', () {
    final session = TrainingSession(
      id: 1,
      mode: TrainingMode.double,
      title: '双人模拟',
      status: TrainingStatus.completed,
      startedAt: DateTime.utc(2026, 7, 24, 7),
      endedAt: DateTime.utc(2026, 7, 24, 8, 40),
      totalDuration: const Duration(minutes: 100),
    );
    const stations = [
      StationRecord(
        id: 1,
        sessionId: 1,
        type: StationType.run,
        runNumber: 1,
        sequenceIndex: 0,
        status: SegmentStatus.completed,
        duration: Duration(minutes: 40),
      ),
      StationRecord(
        id: 2,
        sessionId: 1,
        type: StationType.skiErg,
        sequenceIndex: 1,
        status: SegmentStatus.completed,
        duration: Duration(minutes: 50),
      ),
    ];

    final report = TrainingReport.build(session, stations);

    expect(report.runningDuration, const Duration(minutes: 40));
    expect(report.stationDuration, const Duration(minutes: 50));
    expect(report.transitionDuration, const Duration(minutes: 10));
    expect(report.completedSegments, 2);
  });

  test('report prefers explicitly recorded transition durations', () {
    final session = TrainingSession(
      id: 2,
      mode: TrainingMode.single,
      title: '带转换计时的训练',
      status: TrainingStatus.completed,
      totalDuration: const Duration(minutes: 20),
    );
    final transitionStart = DateTime.utc(2026, 7, 25, 8, 5);
    final stations = [
      StationRecord(
        id: 21,
        sessionId: 2,
        type: StationType.run,
        runNumber: 1,
        sequenceIndex: 0,
        status: SegmentStatus.completed,
        duration: const Duration(minutes: 5),
        transitionStartedAt: transitionStart,
        transitionEndedAt: transitionStart.add(const Duration(seconds: 42)),
        transitionDuration: const Duration(seconds: 42),
      ),
      const StationRecord(
        id: 22,
        sessionId: 2,
        type: StationType.skiErg,
        sequenceIndex: 1,
        status: SegmentStatus.completed,
        duration: Duration(minutes: 5),
      ),
    ];

    final report = TrainingReport.build(session, stations);

    expect(report.transitionDuration, const Duration(seconds: 42));
  });

  test('timer derives elapsed time from timestamps after a background gap', () {
    final sessionStarted = DateTime.utc(2026, 7, 24, 7);
    final segmentStarted = DateTime.utc(2026, 7, 24, 7, 12);
    final resumedAt = DateTime.utc(2026, 7, 24, 8, 5, 30);
    final state = TrainingTimerState(
      session: TrainingSession(
        id: 9,
        mode: TrainingMode.single,
        title: '单人模拟',
        status: TrainingStatus.inProgress,
        startedAt: sessionStarted,
      ),
      stations: [
        StationRecord(
          id: 91,
          sessionId: 9,
          type: StationType.run,
          runNumber: 1,
          sequenceIndex: 0,
          status: SegmentStatus.active,
          startedAt: segmentStarted,
        ),
      ],
      now: resumedAt,
    );

    expect(
        state.totalElapsed, const Duration(hours: 1, minutes: 5, seconds: 30));
    expect(
      state.segmentElapsed,
      const Duration(minutes: 53, seconds: 30),
    );
  });

  test('transition timer derives elapsed time after a background gap', () {
    final transitionStart = DateTime.utc(2026, 7, 25, 8);
    final state = TrainingTimerState(
      session: TrainingSession(
        id: 10,
        mode: TrainingMode.single,
        title: '转换恢复测试',
        status: TrainingStatus.inProgress,
        startedAt: DateTime.utc(2026, 7, 25, 7, 30),
      ),
      stations: [
        StationRecord(
          id: 101,
          sessionId: 10,
          type: StationType.run,
          runNumber: 1,
          sequenceIndex: 0,
          status: SegmentStatus.completed,
          transitionStartedAt: transitionStart,
        ),
        const StationRecord(
          id: 102,
          sessionId: 10,
          type: StationType.skiErg,
          sequenceIndex: 1,
          status: SegmentStatus.pending,
        ),
      ],
      now: transitionStart.add(const Duration(minutes: 3, seconds: 17)),
    );

    expect(state.current, isNull);
    expect(state.isTransitioning, isTrue);
    expect(state.nextAfterTransition?.id, 102);
    expect(state.transitionElapsed, const Duration(minutes: 3, seconds: 17));
    expect(state.undoCandidate?.id, 101);
  });

  test('timer can only undo the station immediately before active station', () {
    final now = DateTime.utc(2026, 7, 26, 8, 10);
    final state = TrainingTimerState(
      session: TrainingSession(
        id: 11,
        mode: TrainingMode.single,
        title: '误触恢复测试',
        status: TrainingStatus.inProgress,
        startedAt: DateTime.utc(2026, 7, 26, 8),
      ),
      stations: [
        StationRecord(
          id: 111,
          sessionId: 11,
          type: StationType.run,
          runNumber: 1,
          sequenceIndex: 0,
          status: SegmentStatus.completed,
          startedAt: DateTime.utc(2026, 7, 26, 8),
          endedAt: DateTime.utc(2026, 7, 26, 8, 5),
        ),
        StationRecord(
          id: 112,
          sessionId: 11,
          type: StationType.skiErg,
          sequenceIndex: 1,
          status: SegmentStatus.active,
          startedAt: DateTime.utc(2026, 7, 26, 8, 5),
        ),
        const StationRecord(
          id: 113,
          sessionId: 11,
          type: StationType.run,
          runNumber: 2,
          sequenceIndex: 2,
          status: SegmentStatus.pending,
        ),
      ],
      now: now,
    );

    expect(state.undoCandidate?.id, 111);
    expect(state.current?.id, 112);
  });

  test('first active station has no undo candidate', () {
    final start = DateTime.utc(2026, 7, 26, 8);
    final state = TrainingTimerState(
      session: TrainingSession(
        id: 12,
        mode: TrainingMode.single,
        title: '首项测试',
        status: TrainingStatus.inProgress,
        startedAt: start,
      ),
      stations: [
        StationRecord(
          id: 121,
          sessionId: 12,
          type: StationType.run,
          runNumber: 1,
          sequenceIndex: 0,
          status: SegmentStatus.active,
          startedAt: start,
        ),
      ],
      now: start,
    );

    expect(state.undoCandidate, isNull);
  });

  test('custom run record keeps its run number and distance', () {
    const record = StationRecord(
      id: 1,
      sessionId: 1,
      type: StationType.run,
      runNumber: 2,
      sequenceIndex: 2,
      status: SegmentStatus.completed,
      targetDistanceMeters: 300,
      duration: Duration(minutes: 2),
    );

    expect(record.displayName, 'RUN 2 · 300 m');
  });

  test('completed station can distinguish target and actual performance', () {
    const record = StationRecord(
      id: 2,
      sessionId: 1,
      type: StationType.wallBall,
      sequenceIndex: 15,
      status: SegmentStatus.completed,
      targetWeightKg: 6,
      targetRepetitions: 100,
      actualWeightKg: 6,
      actualRepetitions: 86,
    );

    expect(record.hasActualPerformance, isTrue);
    expect(record.actualMatchesTarget, isFalse);
    expect(record.actualSpecification, '实际：6 kg · 86 次');
  });

  test('actual performance defaults can be created from station targets', () {
    const record = StationRecord(
      id: 3,
      sessionId: 1,
      type: StationType.sledPush,
      sequenceIndex: 3,
      status: SegmentStatus.completed,
      targetDistanceMeters: 50,
      targetWeightKg: 152,
    );

    final actual = StationActualPerformance.fromTarget(record);
    expect(actual.distanceMeters, 50);
    expect(actual.weightKg, 152);
  });

  test('relay session exposes all three teammate names in order', () {
    final session = TrainingSession(
      id: 12,
      mode: TrainingMode.relay,
      title: '接力训练',
      status: TrainingStatus.inProgress,
      partnerName: '队友甲',
      partnerName2: '队友乙',
      partnerName3: '队友丙',
      startedAt: DateTime.utc(2026, 7, 24),
    );

    expect(session.teammateNames, ['队友甲', '队友乙', '队友丙']);
  });

  test('station record keeps the selected relay athlete name', () {
    const record = StationRecord(
      id: 31,
      sessionId: 12,
      type: StationType.skiErg,
      sequenceIndex: 1,
      status: SegmentStatus.completed,
      athleteName: '队友乙',
    );

    expect(record.athleteName, '队友乙');
  });

  test('timer chooses the first pending project after a dynamic queue change',
      () {
    final transitionStart = DateTime.utc(2026, 7, 29, 8, 5);
    final state = TrainingTimerState(
      session: TrainingSession(
        id: 20,
        mode: TrainingMode.single,
        title: '动态队列测试',
        status: TrainingStatus.inProgress,
        startedAt: DateTime.utc(2026, 7, 29, 8),
      ),
      stations: [
        StationRecord(
          id: 201,
          sessionId: 20,
          type: StationType.run,
          runNumber: 1,
          sequenceIndex: 0,
          status: SegmentStatus.completed,
          startedAt: DateTime.utc(2026, 7, 29, 8),
          transitionStartedAt: transitionStart,
        ),
        const StationRecord(
          id: 204,
          sessionId: 20,
          type: StationType.burpeeBroadJump,
          sequenceIndex: 1,
          status: SegmentStatus.pending,
        ),
        const StationRecord(
          id: 202,
          sessionId: 20,
          type: StationType.skiErg,
          sequenceIndex: 2,
          status: SegmentStatus.pending,
        ),
        StationRecord(
          id: 203,
          sessionId: 20,
          type: StationType.sledPush,
          sequenceIndex: 3,
          status: SegmentStatus.skipped,
          endedAt: DateTime.utc(2026, 7, 29, 8, 4),
          skipReason: '训练中调整',
        ),
      ],
      now: transitionStart,
    );

    expect(state.nextAfterTransition?.id, 204);
    expect(state.pendingStations.map((item) => item.id), [204, 202]);
    expect(state.removedStations.single.id, 203);
    expect(state.executableStations, hasLength(3));
  });

  test('ad-hoc and removed records retain their queue annotations', () {
    const added = StationRecord(
      id: 301,
      sessionId: 30,
      type: StationType.row,
      sequenceIndex: 4,
      status: SegmentStatus.pending,
      origin: StationRecordOrigin.adHoc,
    );
    const removed = StationRecord(
      id: 302,
      sessionId: 30,
      type: StationType.wallBall,
      sequenceIndex: 5,
      status: SegmentStatus.skipped,
      skipReason: '器械占用',
    );

    expect(added.isAdHoc, isTrue);
    expect(removed.wasRemovedBeforeStart, isTrue);
    expect(removed.skipReason, '器械占用');
  });
}
