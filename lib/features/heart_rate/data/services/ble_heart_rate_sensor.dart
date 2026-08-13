import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../domain/models/ble_heart_rate_models.dart';

abstract interface class BleHeartRateSensor {
  Future<bool> requestPermissions();
  Stream<BleHeartRateDevice> scan();
  Stream<DeviceConnectionState> connect(String deviceId);
  Stream<List<int>> measurements(String deviceId);
}

final class ReactiveBleHeartRateSensor implements BleHeartRateSensor {
  ReactiveBleHeartRateSensor({
    FlutterReactiveBle? ble,
    MethodChannel? permissionChannel,
  })  : _ble = ble ?? FlutterReactiveBle(),
        _permissionChannel = permissionChannel ??
            const MethodChannel('hyrox/ble_permissions');

  static final Uuid heartRateService =
      Uuid.parse('0000180d-0000-1000-8000-00805f9b34fb');
  static final Uuid heartRateMeasurement =
      Uuid.parse('00002a37-0000-1000-8000-00805f9b34fb');

  final FlutterReactiveBle _ble;
  final MethodChannel _permissionChannel;

  @override
  Future<bool> requestPermissions() async {
    if (_ble.status == BleStatus.ready) return true;
    final granted =
        await _permissionChannel.invokeMethod<bool>('requestPermissions');
    if (granted != true) return false;
    try {
      await _ble.statusStream
          .firstWhere((status) => status == BleStatus.ready)
          .timeout(const Duration(seconds: 8));
      return true;
    } on TimeoutException {
      return _ble.status == BleStatus.ready;
    }
  }

  @override
  Stream<BleHeartRateDevice> scan() => _ble
      .scanForDevices(
        withServices: [heartRateService],
        scanMode: ScanMode.lowLatency,
      )
      .map(
        (device) => BleHeartRateDevice(
          id: device.id,
          name: device.name,
          rssi: device.rssi,
        ),
      );

  @override
  Stream<DeviceConnectionState> connect(String deviceId) => _ble
      .connectToAdvertisingDevice(
        id: deviceId,
        withServices: [heartRateService],
        prescanDuration: const Duration(seconds: 5),
        servicesWithCharacteristicsToDiscover: {
          heartRateService: [heartRateMeasurement],
        },
        connectionTimeout: const Duration(seconds: 12),
      )
      .map((update) => update.connectionState);

  @override
  Stream<List<int>> measurements(String deviceId) =>
      _ble.subscribeToCharacteristic(
        QualifiedCharacteristic(
          serviceId: heartRateService,
          characteristicId: heartRateMeasurement,
          deviceId: deviceId,
        ),
      );
}
