import 'dart:convert';

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyrox_training_tracker/features/heart_rate/data/services/fit_heart_rate_parser.dart';
import 'package:hyrox_training_tracker/features/heart_rate/data/services/intervals_icu_client.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/heart_rate_models.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/intervals_models.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/repositories/heart_rate_repository.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/services/heart_rate_import_service.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_models.dart';

void main() {
  test('full and segment summaries are calculated from absolute timestamps',
      () {
    final start = DateTime.utc(2026, 7, 23, 0, 21, 19);
    final samples = [
      HeartRateSample(timestamp: start, bpm: 100),
      HeartRateSample(
        timestamp: start.add(const Duration(seconds: 5)),
        bpm: 120,
      ),
      HeartRateSample(
        timestamp: start.add(const Duration(seconds: 10)),
        bpm: 150,
      ),
    ];
    final analysis = HeartRateAnalysis.build(samples, [
      StationRecord(
        id: 7,
        sessionId: 1,
        type: StationType.run,
        sequenceIndex: 0,
        status: SegmentStatus.completed,
        startedAt: start,
        endedAt: start.add(const Duration(seconds: 10)),
      ),
    ]);

    expect(analysis.full?.average, 123);
    expect(analysis.full?.maximum, 150);
    expect(analysis.byStationId[7]?.average, 110);
    expect(analysis.byStationId[7]?.maximum, 120);
  });

  test('matcher returns every heart-rate activity overlapping the session', () {
    final start = DateTime.utc(2026, 7, 23, 0, 30);
    final end = start.add(const Duration(minutes: 30));
    final matched = IntervalsActivityMatcher.overlappingSession(
      sessionStart: start,
      sessionEnd: end,
      activities: [
        IntervalsActivity(
          id: 'ends-at-start',
          name: 'Ends at start',
          startedAt: start.subtract(const Duration(minutes: 10)),
          elapsedTime: const Duration(minutes: 10),
          hasHeartRate: true,
        ),
        IntervalsActivity(
          id: 'overlap-1',
          name: 'Overlap one',
          startedAt: start.subtract(const Duration(minutes: 5)),
          elapsedTime: const Duration(minutes: 10),
          hasHeartRate: true,
        ),
        IntervalsActivity(
          id: 'overlap-2',
          name: 'Overlap two',
          startedAt: start.add(const Duration(minutes: 20)),
          elapsedTime: const Duration(minutes: 20),
          hasHeartRate: true,
        ),
        IntervalsActivity(
          id: 'no-heart-rate',
          name: 'No heart rate',
          startedAt: start,
          elapsedTime: const Duration(minutes: 10),
          hasHeartRate: false,
        ),
        IntervalsActivity(
          id: 'starts-at-end',
          name: 'Starts at end',
          startedAt: end,
          elapsedTime: const Duration(minutes: 10),
          hasHeartRate: true,
        ),
      ],
    );

    expect(matched.map((activity) => activity.id), ['overlap-1', 'overlap-2']);
  });

  test('Intervals streams become absolute UTC heart-rate samples', () async {
    final client = IntervalsIcuClient(
      client: MockClient((request) async {
        expect(request.headers['authorization'], startsWith('Basic '));
        return http.Response(
          jsonEncode([
            {
              'type': 'time',
              'data': [0, 5, 10],
            },
            {
              'type': 'heartrate',
              'data': [84, 90, 100],
            },
          ]),
          200,
        );
      }),
    );
    final activity = IntervalsActivity(
      id: 'i168538762',
      name: 'Morning',
      startedAt: DateTime.utc(2026, 7, 23, 0, 21, 19),
      elapsedTime: const Duration(minutes: 38),
      hasHeartRate: true,
    );

    final samples = await client.getHeartRateStream(
      credentials: const IntervalsCredentials(
        athleteId: 'i123',
        apiKey: 'test-only',
      ),
      activity: activity,
    );

    expect(samples, hasLength(3));
    expect(samples[1].timestamp, DateTime.utc(2026, 7, 23, 0, 21, 24));
    expect(samples[2].bpm, 100);
  });

  test('FIT parser reads timestamped heart-rate record messages', () async {
    final timestamp = DateTime.utc(2026, 7, 23, 0, 21, 19);
    final builder = FitFileBuilder(autoDefine: true)
      ..add(
        RecordMessage()
          ..timestamp = timestamp.millisecondsSinceEpoch
          ..heartRate = 142,
      );

    final samples = await const FitHeartRateParser().parse(
      builder.build().toBytes(),
    );

    expect(samples, hasLength(1));
    expect(samples.single.timestamp, timestamp);
    expect(samples.single.bpm, 142);
  });

  test('local import stores every sample inside the training range', () async {
    final repository = _MemoryHeartRateRepository();
    final service = HeartRateImportService(
      repository: repository,
      intervalsClient: IntervalsIcuClient(
        client: MockClient((_) async => http.Response('[]', 200)),
      ),
    );
    final start = DateTime.utc(2026, 7, 23, 0, 21, 20);
    final session = TrainingSession(
      id: 8,
      mode: TrainingMode.single,
      title: 'FIT test',
      status: TrainingStatus.completed,
      startedAt: start,
      endedAt: start.add(const Duration(seconds: 10)),
    );
    final result = await service.importFit(
      session: session,
      fileName: 'activity.fit',
      samples: [
        HeartRateSample(
          timestamp: start.subtract(const Duration(seconds: 1)),
          bpm: 80,
        ),
        HeartRateSample(timestamp: start, bpm: 100),
        HeartRateSample(
          timestamp: start.add(const Duration(seconds: 5)),
          bpm: 140,
        ),
        HeartRateSample(
          timestamp: start.add(const Duration(seconds: 11)),
          bpm: 90,
        ),
      ],
    );

    expect(result.sampleCount, 2);
    expect(result.importBatchId, 1);
    expect(repository.samples.map((sample) => sample.bpm), [100, 140]);
    expect(repository.externalActivityId, 'activity.fit');
  });
}

final class _MemoryHeartRateRepository implements HeartRateRepository {
  List<HeartRateSample> samples = [];
  String? externalActivityId;

  @override
  Future<int> appendLiveSamples({
    required int sessionId,
    required String deviceId,
    required String deviceName,
    required List<HeartRateSample> samples,
  }) async {
    this.samples.addAll(samples);
    return 1;
  }

  @override
  Future<List<HeartRateImportBatch>> listBatches(int sessionId) async => [];

  @override
  Future<List<HeartRateSample>> listSamples(int sessionId) async => samples;

  @override
  Future<List<HeartRateSample>> listSamplesByBatch(int importBatchId) async =>
      samples;

  @override
  Future<int> replaceSamples({
    required int sessionId,
    required List<HeartRateSample> samples,
    required String source,
    String? externalActivityId,
    String? externalActivityName,
    String? fileName,
  }) async {
    this.samples = [...samples];
    this.externalActivityId = externalActivityId;
    return 1;
  }

  @override
  Future<void> setActiveBatch({
    required int sessionId,
    required int importBatchId,
  }) async {}
}
