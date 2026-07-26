import '../../domain/models/training_models.dart';
import '../../domain/models/training_template.dart';
import '../../domain/repositories/training_repository.dart';
import '../dao/training_dao.dart';

final class SqliteTrainingRepository implements TrainingRepository {
  const SqliteTrainingRepository(this._dao);

  final TrainingDao _dao;

  @override
  Future<int> createAndStartSession({
    required TrainingMode mode,
    required String title,
    required TrainingTemplate template,
    required List<String> teammateNames,
    required DateTime startedAt,
  }) =>
      _dao.createAndStartSession(
        mode: mode,
        title: title,
        template: template,
        teammateNames: teammateNames,
        startedAt: startedAt,
      );

  @override
  Future<TrainingSession?> getSession(int sessionId) async {
    final rows = await _dao.getSession(sessionId);
    return rows.isEmpty ? null : _sessionFromRow(rows.single);
  }

  @override
  Future<TrainingSession?> getActiveSession() async {
    final rows = await _dao.getActiveSession();
    return rows.isEmpty ? null : _sessionFromRow(rows.single);
  }

  @override
  Future<List<TrainingSession>> listSessions() async =>
      (await _dao.listSessions()).map(_sessionFromRow).toList();

  @override
  Future<List<StationRecord>> listStations(int sessionId) async =>
      (await _dao.listStations(sessionId)).map(_stationFromRow).toList();

  @override
  Future<void> activateStation(int stationId, DateTime startedAt) =>
      _dao.activateStation(stationId, startedAt);

  @override
  Future<void> completeStation({
    required int stationId,
    required DateTime endedAt,
    required Duration duration,
    required String athleteName,
  }) =>
      _dao.completeStation(
        stationId: stationId,
        endedAt: endedAt,
        duration: duration,
        athleteName: athleteName,
      );

  @override
  Future<void> skipStation(int stationId, DateTime at) =>
      _dao.skipStation(stationId, at);

  @override
  Future<void> finishStationAndAdvance({
    required int sessionId,
    required int stationId,
    required int? nextStationId,
    required DateTime endedAt,
    required Duration duration,
    required String athleteName,
    required bool skipped,
    required bool startTransition,
    required StationActualPerformance actualPerformance,
  }) =>
      _dao.finishStationAndAdvance(
        sessionId: sessionId,
        stationId: stationId,
        nextStationId: nextStationId,
        endedAt: endedAt,
        duration: duration,
        athleteName: athleteName,
        skipped: skipped,
        startTransition: startTransition,
        actualPerformance: actualPerformance,
      );

  @override
  Future<void> updateStationActualPerformance({
    required int stationId,
    required StationActualPerformance actualPerformance,
  }) =>
      _dao.updateStationActualPerformance(
        stationId: stationId,
        actualPerformance: actualPerformance,
      );

  @override
  Future<void> correctStationBoundary({
    required int sessionId,
    required int previousStationId,
    required int nextStationId,
    required DateTime boundaryAt,
    required DateTime updatedAt,
  }) =>
      _dao.correctStationBoundary(
        sessionId: sessionId,
        previousStationId: previousStationId,
        nextStationId: nextStationId,
        boundaryAt: boundaryAt,
        updatedAt: updatedAt,
      );

  @override
  Future<void> finishTransitionAndActivateNext({
    required int fromStationId,
    required int nextStationId,
    required DateTime at,
  }) =>
      _dao.finishTransitionAndActivateNext(
        fromStationId: fromStationId,
        nextStationId: nextStationId,
        at: at,
      );

  @override
  Future<int> undoLastStationCompletion({
    required int sessionId,
    required DateTime restoredAt,
  }) =>
      _dao.undoLastStationCompletion(
        sessionId: sessionId,
        restoredAt: restoredAt,
      );

  @override
  Future<void> completeSession(int sessionId, DateTime endedAt) =>
      _dao.completeSession(sessionId, endedAt);

  @override
  Future<void> cancelSession(int sessionId, DateTime endedAt) =>
      _dao.cancelSession(sessionId, endedAt);

  @override
  Future<void> deleteSession(int sessionId) => _dao.deleteSession(sessionId);
}

TrainingSession _sessionFromRow(Map<String, Object?> row) => TrainingSession(
      id: row['id']! as int,
      mode: TrainingMode.values.byName(row['mode']! as String),
      title: row['title']! as String,
      partnerName: row['partner_name'] as String?,
      partnerName2: row['partner_name_2'] as String?,
      partnerName3: row['partner_name_3'] as String?,
      status: _trainingStatus(row['status']! as String),
      startedAt: _date(row['started_at_ms']),
      endedAt: _date(row['ended_at_ms']),
      totalDuration: row['total_duration_ms'] == null
          ? null
          : Duration(milliseconds: row['total_duration_ms']! as int),
      avgHeartRate: row['avg_heart_rate'] as int?,
      maxHeartRate: row['max_heart_rate'] as int?,
      heartRateSource: row['heart_rate_source'] as String?,
      heartRateExternalId: row['heart_rate_external_id'] as String?,
      heartRateSampleCount: row['heart_rate_sample_count'] as int?,
      heartRateImportedAt: _date(row['heart_rate_imported_at_ms']),
      note: row['note'] as String?,
      templateId: row['template_id'] as int?,
      templateNameSnapshot: row['template_name_snapshot'] as String?,
    );

StationRecord _stationFromRow(Map<String, Object?> row) => StationRecord(
      id: row['id']! as int,
      sessionId: row['session_id']! as int,
      type: _stationType(row['station_type']! as String),
      runNumber: row['run_number'] as int?,
      sequenceIndex: row['sequence_index']! as int,
      status: _segmentStatus(row['status']! as String),
      segmentKind: TrainingSegmentKind.values.byName(
        row['segment_kind']! as String,
      ),
      startedAt: _date(row['started_at_ms']),
      endedAt: _date(row['ended_at_ms']),
      duration: row['duration_ms'] == null
          ? null
          : Duration(milliseconds: row['duration_ms']! as int),
      athlete: row['athlete'] == null
          ? null
          : AthleteAssignment.values.byName(row['athlete']! as String),
      athleteName: row['athlete_name'] as String?,
      targetDistanceMeters: row['target_distance_meters'] as int?,
      targetResistanceLevel: row['target_resistance_level'] as int?,
      targetWeightKg: (row['target_weight_kg'] as num?)?.toDouble(),
      targetRepetitions: row['target_repetitions'] as int?,
      actualDistanceMeters: row['actual_distance_meters'] as int?,
      actualResistanceLevel: row['actual_resistance_level'] as int?,
      actualWeightKg: (row['actual_weight_kg'] as num?)?.toDouble(),
      actualRepetitions: row['actual_repetitions'] as int?,
      transitionStartedAt: _date(row['transition_started_at_ms']),
      transitionEndedAt: _date(row['transition_ended_at_ms']),
      transitionDuration: row['transition_duration_ms'] == null
          ? null
          : Duration(milliseconds: row['transition_duration_ms']! as int),
    );

DateTime? _date(Object? value) => value == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);

TrainingStatus _trainingStatus(String value) => switch (value) {
      'draft' => TrainingStatus.draft,
      'in_progress' => TrainingStatus.inProgress,
      'completed' => TrainingStatus.completed,
      'cancelled' => TrainingStatus.cancelled,
      _ => throw FormatException('Unknown training status: $value'),
    };

SegmentStatus _segmentStatus(String value) => switch (value) {
      'pending' => SegmentStatus.pending,
      'active' => SegmentStatus.active,
      'completed' => SegmentStatus.completed,
      'skipped' => SegmentStatus.skipped,
      _ => throw FormatException('Unknown segment status: $value'),
    };

StationType _stationType(String value) => switch (value) {
      'run' => StationType.run,
      'ski_erg' => StationType.skiErg,
      'sled_push' => StationType.sledPush,
      'sled_pull' => StationType.sledPull,
      'burpee_broad_jump' => StationType.burpeeBroadJump,
      'row' => StationType.row,
      'farmer_carry' => StationType.farmerCarry,
      'sandbag_lunge' => StationType.sandbagLunge,
      'wall_ball' => StationType.wallBall,
      _ => throw FormatException('Unknown station type: $value'),
    };
