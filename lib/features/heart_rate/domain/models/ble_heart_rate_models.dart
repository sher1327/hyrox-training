enum BleHeartRateConnectionStatus {
  idle,
  scanning,
  connecting,
  connected,
  disconnected,
  unavailable,
  error,
}

final class BleHeartRateDevice {
  const BleHeartRateDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  String get displayName => name.trim().isEmpty ? '未命名心率带' : name;
}

final class BleHeartRateReading {
  const BleHeartRateReading({
    required this.timestamp,
    required this.bpm,
  });

  final DateTime timestamp;
  final int bpm;
}

abstract final class BleHeartRateMeasurementParser {
  static int? parse(List<int> value) {
    if (value.length < 2) return null;
    final usesUint16 = value.first & 0x01 != 0;
    final bpm = usesUint16
        ? value.length < 3
            ? null
            : value[1] | (value[2] << 8)
        : value[1];
    if (bpm == null || bpm <= 0 || bpm > 260) return null;
    return bpm;
  }
}
