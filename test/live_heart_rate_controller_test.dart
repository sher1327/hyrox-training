import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_training_tracker/features/heart_rate/data/services/ble_heart_rate_sensor.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/ble_heart_rate_models.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/heart_rate_models.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/repositories/heart_rate_repository.dart';
import 'package:hyrox_training_tracker/features/heart_rate/presentation/controllers/heart_rate_providers.dart';
import 'package:hyrox_training_tracker/features/heart_rate/presentation/controllers/live_heart_rate_controller.dart';

void main() {
  test('stopping waits for an active flush and persists tail samples',
      () async {
    final sensor = _FakeBleHeartRateSensor();
    final repository = _DelayedHeartRateRepository();
    final container = ProviderContainer(
      overrides: [
        bleHeartRateSensorProvider.overrideWithValue(sensor),
        heartRateRepositoryFutureProvider.overrideWith(
          (ref) async => repository,
        ),
      ],
    );
    final subscription = container.listen(
      liveHeartRateControllerProvider(7),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await sensor.close();
    });

    final controller =
        container.read(liveHeartRateControllerProvider(7).notifier);
    await controller.connect(
      const BleHeartRateDevice(id: 'belt-1', name: 'Polar H10', rssi: -40),
    );
    sensor.connection.add(DeviceConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    for (final bpm in [140, 141, 142, 143, 144]) {
      sensor.measurementValues.add([0, bpm]);
    }
    await repository.firstWriteStarted.future;

    sensor.measurementValues.add([0, 145]);
    sensor.measurementValues.add([0, 146]);
    final stopped = controller.stopRecording();
    repository.releaseFirstWrite.complete();
    await stopped;

    expect(repository.samples.map((sample) => sample.bpm), [
      140,
      141,
      142,
      143,
      144,
      145,
      146,
    ]);
    expect(
      container.read(liveHeartRateControllerProvider(7)).savedSampleCount,
      7,
    );
  });
}

final class _FakeBleHeartRateSensor implements BleHeartRateSensor {
  final connection = StreamController<DeviceConnectionState>.broadcast(
    sync: true,
  );
  final measurementValues = StreamController<List<int>>.broadcast(sync: true);

  @override
  Stream<DeviceConnectionState> connect(String deviceId) => connection.stream;

  @override
  Stream<List<int>> measurements(String deviceId) => measurementValues.stream;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Stream<BleHeartRateDevice> scan() => const Stream.empty();

  Future<void> close() async {
    await connection.close();
    await measurementValues.close();
  }
}

final class _DelayedHeartRateRepository implements HeartRateRepository {
  final firstWriteStarted = Completer<void>();
  final releaseFirstWrite = Completer<void>();
  final List<HeartRateSample> samples = [];
  var _writes = 0;

  @override
  Future<int> appendLiveSamples({
    required int sessionId,
    required String deviceId,
    required String deviceName,
    required List<HeartRateSample> samples,
  }) async {
    _writes++;
    if (_writes == 1) {
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
    }
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
  }) async =>
      1;

  @override
  Future<void> setActiveBatch({
    required int sessionId,
    required int importBatchId,
  }) async {}
}
