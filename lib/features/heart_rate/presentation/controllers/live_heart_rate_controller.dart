import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../data/services/ble_heart_rate_sensor.dart';
import '../../domain/models/ble_heart_rate_models.dart';
import '../../domain/models/heart_rate_models.dart';
import 'heart_rate_providers.dart';

final bleHeartRateSensorProvider = Provider<BleHeartRateSensor>(
  (ref) => ReactiveBleHeartRateSensor(),
);

final liveHeartRateControllerProvider = NotifierProvider.autoDispose
    .family<LiveHeartRateController, LiveHeartRateState, int>(
  LiveHeartRateController.new,
);

final class LiveHeartRateState {
  const LiveHeartRateState({
    this.status = BleHeartRateConnectionStatus.idle,
    this.devices = const [],
    this.connectedDevice,
    this.currentBpm,
    this.savedSampleCount = 0,
    this.message,
  });

  final BleHeartRateConnectionStatus status;
  final List<BleHeartRateDevice> devices;
  final BleHeartRateDevice? connectedDevice;
  final int? currentBpm;
  final int savedSampleCount;
  final String? message;

  bool get isConnected =>
      status == BleHeartRateConnectionStatus.connected;

  LiveHeartRateState copyWith({
    BleHeartRateConnectionStatus? status,
    List<BleHeartRateDevice>? devices,
    BleHeartRateDevice? connectedDevice,
    int? currentBpm,
    int? savedSampleCount,
    String? message,
    bool clearMessage = false,
  }) =>
      LiveHeartRateState(
        status: status ?? this.status,
        devices: devices ?? this.devices,
        connectedDevice: connectedDevice ?? this.connectedDevice,
        currentBpm: currentBpm ?? this.currentBpm,
        savedSampleCount: savedSampleCount ?? this.savedSampleCount,
        message: clearMessage ? null : message ?? this.message,
      );
}

final class LiveHeartRateController
    extends AutoDisposeFamilyNotifier<LiveHeartRateState, int> {
  late BleHeartRateSensor _sensor;
  StreamSubscription<BleHeartRateDevice>? _scanSubscription;
  StreamSubscription<DeviceConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _measurementSubscription;
  Timer? _scanTimer;
  Timer? _flushTimer;
  final List<HeartRateSample> _buffer = [];
  bool _flushing = false;

  @override
  LiveHeartRateState build(int arg) {
    _sensor = ref.read(bleHeartRateSensorProvider);
    ref.onDispose(() {
      _scanTimer?.cancel();
      _flushTimer?.cancel();
      unawaited(_scanSubscription?.cancel());
      unawaited(_measurementSubscription?.cancel());
      unawaited(_connectionSubscription?.cancel());
      unawaited(_flush());
    });
    return const LiveHeartRateState();
  }

  Future<void> startScan() async {
    await _scanSubscription?.cancel();
    _scanTimer?.cancel();
    final granted = await _sensor.requestPermissions();
    if (!granted) {
      state = state.copyWith(
        status: BleHeartRateConnectionStatus.unavailable,
        message: '需要蓝牙扫描和连接权限',
      );
      return;
    }
    state = state.copyWith(
      status: BleHeartRateConnectionStatus.scanning,
      devices: const [],
      clearMessage: true,
    );
    final found = <String, BleHeartRateDevice>{};
    _scanSubscription = _sensor.scan().listen(
      (device) {
        found[device.id] = device;
        final devices = found.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        state = state.copyWith(devices: devices);
      },
      onError: (Object error) {
        state = state.copyWith(
          status: BleHeartRateConnectionStatus.error,
          message: '扫描失败：$error',
        );
      },
    );
    _scanTimer = Timer(const Duration(seconds: 12), () {
      unawaited(_scanSubscription?.cancel());
      if (state.status == BleHeartRateConnectionStatus.scanning) {
        state = state.copyWith(
          status: BleHeartRateConnectionStatus.idle,
          message: state.devices.isEmpty ? '没有发现标准 BLE 心率设备' : null,
        );
      }
    });
  }

  Future<void> connect(BleHeartRateDevice device) async {
    await _scanSubscription?.cancel();
    await _measurementSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _scanTimer?.cancel();
    state = state.copyWith(
      status: BleHeartRateConnectionStatus.connecting,
      connectedDevice: device,
      clearMessage: true,
    );
    _connectionSubscription = _sensor.connect(device.id).listen(
      (connectionState) {
        switch (connectionState) {
          case DeviceConnectionState.connected:
            state = state.copyWith(
              status: BleHeartRateConnectionStatus.connected,
              connectedDevice: device,
              clearMessage: true,
            );
            _subscribe(device);
            break;
          case DeviceConnectionState.connecting:
            state = state.copyWith(
              status: BleHeartRateConnectionStatus.connecting,
            );
            break;
          case DeviceConnectionState.disconnecting:
          case DeviceConnectionState.disconnected:
            state = state.copyWith(
              status: BleHeartRateConnectionStatus.disconnected,
              message: '心率带已断开，可重新扫描连接',
            );
            break;
        }
      },
      onError: (Object error) {
        state = state.copyWith(
          status: BleHeartRateConnectionStatus.error,
          message: '连接失败：$error',
        );
      },
    );
  }

  void _subscribe(BleHeartRateDevice device) {
    unawaited(_measurementSubscription?.cancel());
    _measurementSubscription = _sensor.measurements(device.id).listen(
      (value) {
        final bpm = BleHeartRateMeasurementParser.parse(value);
        if (bpm == null) return;
        _buffer.add(
          HeartRateSample(timestamp: DateTime.now().toUtc(), bpm: bpm),
        );
        state = state.copyWith(currentBpm: bpm);
        if (_buffer.length >= 5) unawaited(_flush());
      },
      onError: (Object error) {
        state = state.copyWith(message: '心率读取中断：$error');
      },
    );
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_flush()),
    );
  }

  Future<void> stopRecording() async {
    _scanTimer?.cancel();
    _flushTimer?.cancel();
    await _scanSubscription?.cancel();
    await _measurementSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _flush();
    state = state.copyWith(
      status: BleHeartRateConnectionStatus.disconnected,
      message: state.savedSampleCount == 0 ? '本次没有收到心率采样' : '心率记录已保存',
    );
  }

  Future<void> _flush() async {
    final device = state.connectedDevice;
    if (_flushing || device == null || _buffer.isEmpty) return;
    _flushing = true;
    final samples = List<HeartRateSample>.of(_buffer);
    _buffer.clear();
    try {
      final repository =
          await ref.read(heartRateRepositoryFutureProvider.future);
      await repository.appendLiveSamples(
        sessionId: arg,
        deviceId: device.id,
        deviceName: device.displayName,
        samples: samples,
      );
      state = state.copyWith(
        savedSampleCount: state.savedSampleCount + samples.length,
      );
      ref.invalidate(heartRateAnalysisProvider(arg));
      ref.invalidate(heartRateSourcesProvider(arg));
    } catch (error) {
      _buffer.insertAll(0, samples);
      state = state.copyWith(message: '心率保存失败：$error');
    } finally {
      _flushing = false;
    }
  }
}
