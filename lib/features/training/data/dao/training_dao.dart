import 'package:sqflite/sqflite.dart';

import '../../domain/models/training_models.dart';
import '../../domain/models/training_exceptions.dart';
import '../../domain/models/training_template.dart';

final class TrainingDao {
  const TrainingDao(this.db);

  final Database db;

  Future<int> createAndStartSession({
    required TrainingMode mode,
    required String title,
    required TrainingTemplate template,
    required List<String> teammateNames,
    required DateTime startedAt,
  }) async {
    return db.transaction((txn) async {
      final active = await txn.query(
        'training_session',
        columns: ['id'],
        where: "status = 'in_progress'",
        limit: 1,
      );
      if (active.isNotEmpty) {
        throw ActiveTrainingExistsException(active.single['id']! as int);
      }
      final now = startedAt.millisecondsSinceEpoch;
      final sessionId = await txn.insert('training_session', {
        'mode': mode.name,
        'title': title,
        'partner_name': teammateNames.firstOrNull,
        'partner_name_2': teammateNames.elementAtOrNull(1),
        'partner_name_3': teammateNames.elementAtOrNull(2),
        'template_id': template.id,
        'template_name_snapshot': template.name,
        'status': 'in_progress',
        'started_at_ms': now,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      var runNumber = 0;
      for (var index = 0; index < template.segments.length; index++) {
        final segment = template.segments[index];
        if (segment.type == StationType.run) runNumber++;
        await txn.insert('station_record', {
          'session_id': sessionId,
          'station_type': _stationTypeToDb(segment.type),
          'segment_kind': segment.segmentKind.name,
          'run_number': segment.type == StationType.run ? runNumber : null,
          'sequence_index': index,
          'status': index == 0 ? 'active' : 'pending',
          'started_at_ms': index == 0 ? now : null,
          'accumulated_ms': 0,
          'target_distance_meters': segment.targetDistanceMeters,
          'target_resistance_level': segment.targetResistanceLevel,
          'target_weight_kg': segment.targetWeightKg,
          'target_repetitions': segment.targetRepetitions,
        });
      }
      return sessionId;
    });
  }

  Future<List<Map<String, Object?>>> listStations(int sessionId) => db.query(
        'station_record',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'sequence_index ASC',
      );

  Future<List<Map<String, Object?>>> listSessions() => db.query(
        'training_session',
        orderBy: 'started_at_ms DESC',
      );

  Future<List<Map<String, Object?>>> getActiveSession() => db.query(
        'training_session',
        where: "status = 'in_progress'",
        orderBy: 'started_at_ms DESC',
        limit: 1,
      );

  Future<List<Map<String, Object?>>> getSession(int sessionId) => db.query(
        'training_session',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

  Future<void> completeStation({
    required int stationId,
    required DateTime endedAt,
    required Duration duration,
    required String athleteName,
  }) =>
      db.update(
        'station_record',
        {
          'status': 'completed',
          'ended_at_ms': endedAt.millisecondsSinceEpoch,
          'duration_ms': duration.inMilliseconds,
          'accumulated_ms': duration.inMilliseconds,
          'athlete': switch (athleteName) {
            '我' => 'self',
            '共同完成' => 'both',
            _ => 'partner',
          },
          'athlete_name': athleteName,
        },
        where: 'id = ?',
        whereArgs: [stationId],
      );

  Future<void> activateStation(int stationId, DateTime startedAt) => db.update(
        'station_record',
        {
          'status': 'active',
          'started_at_ms': startedAt.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [stationId],
      );

  Future<void> skipStation(int stationId, DateTime at) => db.update(
        'station_record',
        {'status': 'skipped', 'ended_at_ms': at.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [stationId],
      );

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
      db.transaction((txn) async {
        final endedAtMs = endedAt.millisecondsSinceEpoch;
        final values = <String, Object?>{
          'status': skipped ? 'skipped' : 'completed',
          'ended_at_ms': endedAtMs,
          if (!skipped) ...{
            'duration_ms': duration.inMilliseconds,
            'accumulated_ms': duration.inMilliseconds,
            'athlete': switch (athleteName) {
              '我' => 'self',
              '共同完成' => 'both',
              _ => 'partner',
            },
            'athlete_name': athleteName,
            'actual_distance_meters': actualPerformance.distanceMeters,
            'actual_resistance_level': actualPerformance.resistanceLevel,
            'actual_weight_kg': actualPerformance.weightKg,
            'actual_repetitions': actualPerformance.repetitions,
          },
          if (nextStationId != null && startTransition)
            'transition_started_at_ms': endedAtMs,
        };
        final updated = await txn.update(
          'station_record',
          values,
          where: "id = ? AND status = 'active'",
          whereArgs: [stationId],
        );
        if (updated != 1) throw StateError('当前项目状态已发生变化');

        if (nextStationId == null) {
          await txn.rawUpdate(
            '''UPDATE training_session
               SET status = 'completed', ended_at_ms = ?,
                   total_duration_ms = ? - started_at_ms, updated_at_ms = ?
               WHERE id = ? AND status = 'in_progress' ''',
            [endedAtMs, endedAtMs, endedAtMs, sessionId],
          );
        } else if (!startTransition) {
          final activated = await txn.update(
            'station_record',
            {'status': 'active', 'started_at_ms': endedAtMs},
            where: "id = ? AND status = 'pending'",
            whereArgs: [nextStationId],
          );
          if (activated != 1) throw StateError('下一项目状态已发生变化');
        }
      });

  Future<void> updateStationActualPerformance({
    required int stationId,
    required StationActualPerformance actualPerformance,
  }) async {
    final updated = await db.update(
      'station_record',
      {
        'actual_distance_meters': actualPerformance.distanceMeters,
        'actual_resistance_level': actualPerformance.resistanceLevel,
        'actual_weight_kg': actualPerformance.weightKg,
        'actual_repetitions': actualPerformance.repetitions,
      },
      where: "id = ? AND status = 'completed'",
      whereArgs: [stationId],
    );
    if (updated != 1) throw StateError('只能填写已完成项目的实际数据');
  }

  Future<void> finishTransitionAndActivateNext({
    required int fromStationId,
    required int nextStationId,
    required DateTime at,
  }) =>
      db.transaction((txn) async {
        final atMs = at.millisecondsSinceEpoch;
        final transitioned = await txn.rawUpdate(
          '''UPDATE station_record
             SET transition_ended_at_ms = ?,
                 transition_duration_ms = MAX(0, ? - transition_started_at_ms)
             WHERE id = ?
               AND transition_started_at_ms IS NOT NULL
               AND transition_ended_at_ms IS NULL''',
          [atMs, atMs, fromStationId],
        );
        if (transitioned != 1) throw StateError('转换计时状态已发生变化');
        final activated = await txn.update(
          'station_record',
          {'status': 'active', 'started_at_ms': atMs},
          where: "id = ? AND status = 'pending'",
          whereArgs: [nextStationId],
        );
        if (activated != 1) throw StateError('下一项目状态已发生变化');
      });

  /// Restores only the immediately preceding completed/skipped station.
  ///
  /// It supports all three states produced by the timer flow:
  /// 1. transition is running and the next station is pending;
  /// 2. the next station was activated directly;
  /// 3. the final station completed the whole session.
  Future<int> undoLastStationCompletion({
    required int sessionId,
    required DateTime restoredAt,
  }) =>
      db.transaction((txn) async {
        final sessions = await txn.query(
          'training_session',
          columns: ['id', 'status'],
          where: 'id = ?',
          whereArgs: [sessionId],
          limit: 1,
        );
        if (sessions.isEmpty) throw StateError('训练记录不存在');
        final sessionStatus = sessions.single['status']! as String;
        if (sessionStatus != 'in_progress' && sessionStatus != 'completed') {
          throw StateError('当前训练状态不允许撤销完成');
        }

        final stations = await txn.query(
          'station_record',
          where: 'session_id = ?',
          whereArgs: [sessionId],
          orderBy: 'sequence_index ASC',
        );
        if (stations.isEmpty) throw StateError('训练没有项目记录');

        Map<String, Object?>? source;
        Map<String, Object?>? activeNext;
        final transitions = stations
            .where(
              (row) =>
                  row['transition_started_at_ms'] != null &&
                  row['transition_ended_at_ms'] == null,
            )
            .toList();
        final active =
            stations.where((row) => row['status'] == 'active').toList();
        if (transitions.length > 1 || active.length > 1) {
          throw StateError('训练项目状态异常，无法安全撤销');
        }

        if (transitions.isNotEmpty) {
          source = transitions.single;
        } else if (active.isNotEmpty) {
          activeNext = active.single;
          final previousIndex = (activeNext['sequence_index']! as int) - 1;
          final previous = stations
              .where((row) => row['sequence_index'] == previousIndex)
              .toList();
          source = previous.isEmpty ? null : previous.single;
        } else if (sessionStatus == 'completed') {
          source = stations.last;
        }

        if (source == null ||
            (source['status'] != 'completed' &&
                source['status'] != 'skipped')) {
          throw StateError('没有可以撤销的上一项目');
        }
        if (source['started_at_ms'] == null) {
          throw StateError('上一项目缺少开始时间，无法恢复计时');
        }
        final sourceIndex = source['sequence_index']! as int;
        if (sessionStatus == 'completed' &&
            sourceIndex != (stations.last['sequence_index']! as int)) {
          throw StateError('只能撤销最后完成的项目');
        }
        if (activeNext != null &&
            activeNext['sequence_index'] != sourceIndex + 1) {
          throw StateError('只能撤销当前项目的上一项');
        }
        final laterChanged = stations.any(
          (row) =>
              (row['sequence_index']! as int) > sourceIndex &&
              row['id'] != activeNext?['id'] &&
              row['status'] != 'pending',
        );
        if (laterChanged) throw StateError('后续项目已有记录，无法撤销');

        if (activeNext != null) {
          final reset = await txn.update(
            'station_record',
            {
              'status': 'pending',
              'started_at_ms': null,
              'ended_at_ms': null,
              'duration_ms': null,
              'accumulated_ms': 0,
              'athlete': null,
              'athlete_name': null,
              'actual_distance_meters': null,
              'actual_resistance_level': null,
              'actual_weight_kg': null,
              'actual_repetitions': null,
              'transition_started_at_ms': null,
              'transition_ended_at_ms': null,
              'transition_duration_ms': null,
            },
            where: "id = ? AND status = 'active'",
            whereArgs: [activeNext['id']],
          );
          if (reset != 1) throw StateError('当前项目状态已发生变化');
        }

        final restored = await txn.update(
          'station_record',
          {
            'status': 'active',
            'ended_at_ms': null,
            'duration_ms': null,
            'accumulated_ms': 0,
            'athlete': null,
            'athlete_name': null,
            'actual_distance_meters': null,
            'actual_resistance_level': null,
            'actual_weight_kg': null,
            'actual_repetitions': null,
            'transition_started_at_ms': null,
            'transition_ended_at_ms': null,
            'transition_duration_ms': null,
          },
          where: "id = ? AND status IN ('completed', 'skipped')",
          whereArgs: [source['id']],
        );
        if (restored != 1) throw StateError('上一项目状态已发生变化');

        final restoredAtMs = restoredAt.millisecondsSinceEpoch;
        if (sessionStatus == 'completed') {
          final reopened = await txn.update(
            'training_session',
            {
              'status': 'in_progress',
              'ended_at_ms': null,
              'total_duration_ms': null,
              'updated_at_ms': restoredAtMs,
            },
            where: "id = ? AND status = 'completed'",
            whereArgs: [sessionId],
          );
          if (reopened != 1) throw StateError('训练状态已发生变化');
        } else {
          await txn.update(
            'training_session',
            {'updated_at_ms': restoredAtMs},
            where: "id = ? AND status = 'in_progress'",
            whereArgs: [sessionId],
          );
        }
        return source['id']! as int;
      });

  Future<void> completeSession(int sessionId, DateTime endedAt) async {
    await db.rawUpdate(
      '''UPDATE training_session
         SET status = 'completed', ended_at_ms = ?,
             total_duration_ms = ? - started_at_ms, updated_at_ms = ?
         WHERE id = ?''',
      [
        endedAt.millisecondsSinceEpoch,
        endedAt.millisecondsSinceEpoch,
        endedAt.millisecondsSinceEpoch,
        sessionId,
      ],
    );
  }

  Future<void> cancelSession(int sessionId, DateTime endedAt) =>
      db.transaction((txn) async {
        final endedAtMs = endedAt.millisecondsSinceEpoch;
        await txn.update(
          'station_record',
          {
            'status': 'skipped',
            'ended_at_ms': endedAtMs,
          },
          where: "session_id = ? AND status = 'active'",
          whereArgs: [sessionId],
        );
        await txn.rawUpdate(
          '''UPDATE station_record
             SET transition_ended_at_ms = ?,
                 transition_duration_ms = MAX(0, ? - transition_started_at_ms)
             WHERE session_id = ?
               AND transition_started_at_ms IS NOT NULL
               AND transition_ended_at_ms IS NULL''',
          [endedAtMs, endedAtMs, sessionId],
        );
        await txn.rawUpdate(
          '''UPDATE training_session
             SET status = 'cancelled', ended_at_ms = ?,
                 total_duration_ms = MAX(0, ? - started_at_ms),
                 updated_at_ms = ?
             WHERE id = ? AND status = 'in_progress' ''',
          [endedAtMs, endedAtMs, endedAtMs, sessionId],
        );
      });

  Future<void> deleteSession(int sessionId) async {
    final deleted = await db.delete(
      'training_session',
      where: "id = ? AND status <> 'in_progress'",
      whereArgs: [sessionId],
    );
    if (deleted == 0) {
      throw StateError('进行中的训练需要先取消，不能直接删除');
    }
  }
}

String _stationTypeToDb(StationType type) => switch (type) {
      StationType.run => 'run',
      StationType.skiErg => 'ski_erg',
      StationType.sledPush => 'sled_push',
      StationType.sledPull => 'sled_pull',
      StationType.burpeeBroadJump => 'burpee_broad_jump',
      StationType.row => 'row',
      StationType.farmerCarry => 'farmer_carry',
      StationType.sandbagLunge => 'sandbag_lunge',
      StationType.wallBall => 'wall_ball',
    };

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;

  T? elementAtOrNull(int index) => index < length ? this[index] : null;
}
