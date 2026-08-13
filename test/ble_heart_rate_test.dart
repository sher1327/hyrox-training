import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/ble_heart_rate_models.dart';

void main() {
  test('parses Bluetooth SIG 8-bit heart-rate measurement', () {
    expect(BleHeartRateMeasurementParser.parse([0x00, 152]), 152);
  });

  test('parses Bluetooth SIG 16-bit heart-rate measurement', () {
    expect(BleHeartRateMeasurementParser.parse([0x01, 200, 0]), 200);
  });

  test('rejects malformed and physiologically invalid measurements', () {
    expect(BleHeartRateMeasurementParser.parse([]), isNull);
    expect(BleHeartRateMeasurementParser.parse([0x01, 100]), isNull);
    expect(BleHeartRateMeasurementParser.parse([0x00, 0]), isNull);
    expect(BleHeartRateMeasurementParser.parse([0x01, 5, 1]), isNull);
  });
}
