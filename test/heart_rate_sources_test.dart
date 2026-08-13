import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_training_tracker/features/heart_rate/domain/models/heart_rate_models.dart';
import 'package:hyrox_training_tracker/features/training/domain/models/training_models.dart';

void main() {
  test('training feelings round-trip through database values', () {
    for (final feeling in TrainingFeeling.values) {
      expect(
        TrainingFeelingLabel.fromDatabase(feeling.databaseValue),
        feeling,
      );
    }
  });

  test('heart-rate batches expose human-readable source labels', () {
    final batch = HeartRateImportBatch(
      id: 1,
      sessionId: 2,
      source: HeartRateSources.ble,
      externalActivityName: 'Polar H10',
      importedAt: DateTime.utc(2026),
      sampleCount: 30,
      average: 150,
      maximum: 180,
      isActive: true,
    );

    expect(batch.sourceLabel, '实时心率带');
    expect(batch.displayName, 'Polar H10');
  });
}
