import 'package:sqflite/sqflite.dart';

import '../../domain/models/concept2_models.dart';

final class Concept2Dao {
  const Concept2Dao(this.db);

  final Database db;

  Future<List<Map<String, Object?>>> getForSession(int sessionId) => db.query(
        'concept2_result',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

  Future<List<Map<String, Object?>>> listIntervals(int resultRowId) => db.query(
        'concept2_interval',
        where: 'concept2_result_row_id = ?',
        whereArgs: [resultRowId],
        orderBy: 'sequence_index ASC',
      );

  Future<List<Map<String, Object?>>> listStrokes(int resultRowId) => db.query(
        'concept2_stroke',
        where: 'concept2_result_row_id = ?',
        whereArgs: [resultRowId],
        orderBy: 'sequence_index ASC',
      );

  Future<void> saveForSession({
    required int sessionId,
    required Concept2Result result,
    required DateTime importedAt,
  }) =>
      db.transaction((txn) async {
        await txn.delete(
          'concept2_result',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        final resultRowId = await txn.insert('concept2_result', {
          'session_id': sessionId,
          'external_result_id': result.id,
          'machine_type': result.machine.apiValue,
          'ended_at_ms': result.endedAt.millisecondsSinceEpoch,
          'distance_meters': result.distanceMeters,
          'work_time_tenths': result.workTimeTenths,
          'rest_time_tenths': result.restTimeTenths,
          'workout_type': result.workoutType,
          'stroke_rate': result.strokeRate,
          'stroke_count': result.strokeCount,
          'drag_factor': result.dragFactor,
          'calories_total': result.calories,
          'source': result.source,
          'imported_at_ms': importedAt.millisecondsSinceEpoch,
        });
        final batch = txn.batch();
        for (final interval in result.intervals) {
          batch.insert('concept2_interval', {
            'concept2_result_row_id': resultRowId,
            'sequence_index': interval.sequenceIndex,
            'interval_kind': interval.kind,
            'time_tenths': interval.timeTenths,
            'rest_time_tenths': interval.restTimeTenths,
            'distance_meters': interval.distanceMeters,
            'rest_distance_meters': interval.restDistanceMeters,
            'stroke_rate': interval.strokeRate,
            'calories_total': interval.calories,
          });
        }
        for (final stroke in result.strokes) {
          batch.insert('concept2_stroke', {
            'concept2_result_row_id': resultRowId,
            'sequence_index': stroke.sequenceIndex,
            'stroke_time_tenths': stroke.timeTenths,
            'cumulative_work_tenths': stroke.cumulativeWorkTenths,
            'distance_decimeters': stroke.distanceDecimeters,
            'pace_tenths': stroke.paceTenths,
            'stroke_rate': stroke.strokeRate,
            'heart_rate': stroke.heartRate,
          });
        }
        await batch.commit(noResult: true);
      });
}
