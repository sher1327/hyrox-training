import '../../domain/models/concept2_models.dart';
import '../../domain/repositories/concept2_repository.dart';
import '../dao/concept2_dao.dart';

final class SqliteConcept2Repository implements Concept2Repository {
  const SqliteConcept2Repository(this._dao);

  final Concept2Dao _dao;

  @override
  Future<Concept2Result?> getForSession(int sessionId) async {
    final rows = await _dao.getForSession(sessionId);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final intervals = (await _dao.listIntervals(row['id']! as int))
        .map(
          (value) => Concept2Interval(
            sequenceIndex: value['sequence_index']! as int,
            kind: value['interval_kind']! as String,
            timeTenths: value['time_tenths']! as int,
            restTimeTenths: value['rest_time_tenths']! as int,
            distanceMeters: value['distance_meters']! as int,
            restDistanceMeters: value['rest_distance_meters']! as int,
            strokeRate: value['stroke_rate'] as int?,
            calories: value['calories_total'] as int?,
          ),
        )
        .toList();
    return Concept2Result(
      id: row['external_result_id']! as int,
      machine: Concept2Machine.values.byName(row['machine_type']! as String),
      endedAt: DateTime.fromMillisecondsSinceEpoch(
        row['ended_at_ms']! as int,
        isUtc: true,
      ),
      distanceMeters: row['distance_meters']! as int,
      workTimeTenths: row['work_time_tenths']! as int,
      restTimeTenths: row['rest_time_tenths']! as int,
      workoutType: row['workout_type']! as String,
      strokeRate: row['stroke_rate'] as int?,
      strokeCount: row['stroke_count'] as int?,
      dragFactor: row['drag_factor'] as int?,
      calories: row['calories_total'] as int?,
      source: row['source'] as String?,
      importedAt: DateTime.fromMillisecondsSinceEpoch(
        row['imported_at_ms']! as int,
        isUtc: true,
      ),
      intervals: intervals,
    );
  }

  @override
  Future<void> saveForSession({
    required int sessionId,
    required Concept2Result result,
    required DateTime importedAt,
  }) =>
      _dao.saveForSession(
        sessionId: sessionId,
        result: result,
        importedAt: importedAt,
      );
}
