import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_schema.dart';

final class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<String> get databasePath async {
    final root = await getDatabasesPath();
    return p.join(root, 'hyrox.db');
  }

  /// Flushes any pending WAL pages so a file copy represents one consistent
  /// point in time. Backup operations are only exposed away from the live
  /// timer, so no application write can race the subsequent copy.
  Future<void> prepareForSnapshot() async {
    final db = await database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } on DatabaseException {
      // Databases using the DELETE journal mode do not have WAL pages.
    }
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    await current?.close();
  }

  Future<void> reopen() async {
    await database;
  }

  Future<Database> _open() async {
    return openDatabase(
      await databasePath,
      version: DatabaseSchema.version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute(DatabaseSchema.createTrainingTemplate);
        await db.execute(DatabaseSchema.createTemplateSegment);
        await db.execute(DatabaseSchema.createTrainingSession);
        await db.execute(DatabaseSchema.createStationRecord);
        await db.execute(DatabaseSchema.createHeartRateImport);
        await db.execute(DatabaseSchema.createHeartRateSample);
        await _seedBuiltInTemplates(db);
        for (final statement in DatabaseSchema.indexes) {
          await db.execute(statement);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Keep the newest active session and safely close any older duplicates
          // before adding the database-level single-active-session constraint.
          await db.execute('''
UPDATE training_session
SET status = 'cancelled',
    ended_at_ms = COALESCE(ended_at_ms, updated_at_ms),
    total_duration_ms = COALESCE(
      total_duration_ms,
      MAX(0, updated_at_ms - started_at_ms)
    )
WHERE status = 'in_progress'
  AND id <> (
    SELECT id FROM training_session
    WHERE status = 'in_progress'
    ORDER BY started_at_ms DESC, id DESC
    LIMIT 1
  )
''');
          await db.execute('''
UPDATE station_record
SET status = 'skipped'
WHERE status = 'active'
  AND session_id IN (
    SELECT id FROM training_session WHERE status = 'cancelled'
  )
''');
          await db.execute(DatabaseSchema.uniqueActiveSessionIndex);
        }
        if (oldVersion < 3) {
          await db.execute(DatabaseSchema.createTrainingTemplate);
          await db.execute(DatabaseSchema.createTemplateSegment);
          final templateId = await _seedStandardTemplate(db);
          await db.execute(
            'ALTER TABLE training_session ADD COLUMN template_id INTEGER '
            'REFERENCES training_template(id) ON DELETE SET NULL',
          );
          await db.execute(
            'ALTER TABLE training_session ADD COLUMN template_name_snapshot TEXT',
          );
          await db.update(
            'training_session',
            {
              'template_id': templateId,
              'template_name_snapshot': '标准 HYROX 模拟',
            },
          );

          await db.execute('DROP INDEX IF EXISTS idx_station_session');
          await db.execute(
            'ALTER TABLE station_record RENAME TO station_record_v2',
          );
          await db.execute(DatabaseSchema.createStationRecord);
          await db.execute('''
INSERT INTO station_record (
  id, session_id, segment_kind, station_type, run_number, sequence_index, status,
  started_at_ms, ended_at_ms, duration_ms, accumulated_ms, athlete,
  target_distance_meters, target_weight_kg, target_repetitions, remark
)
SELECT
  id, session_id, 'station', station_type, run_number, sequence_index, status,
  started_at_ms, ended_at_ms, duration_ms, accumulated_ms, athlete,
  CASE WHEN station_type = 'run' THEN COALESCE(distance_meters, 1000)
       ELSE distance_meters END,
  weight_kg, repetitions, remark
FROM station_record_v2
''');
          await db.execute('DROP TABLE station_record_v2');
          await db.execute(
            'CREATE INDEX idx_station_session '
            'ON station_record(session_id, sequence_index)',
          );
          await db.execute(
            'CREATE INDEX idx_template_segment_order '
            'ON template_segment(template_id, sequence_index)',
          );
        }
        if (oldVersion < 4) {
          if (!await _hasColumn(db, 'training_session', 'partner_name_2')) {
            await db.execute(
              'ALTER TABLE training_session ADD COLUMN partner_name_2 TEXT',
            );
          }
          if (!await _hasColumn(db, 'training_session', 'partner_name_3')) {
            await db.execute(
              'ALTER TABLE training_session ADD COLUMN partner_name_3 TEXT',
            );
          }
          if (!await _hasColumn(db, 'station_record', 'athlete_name')) {
            await db.execute(
              'ALTER TABLE station_record ADD COLUMN athlete_name TEXT',
            );
          }
          await db.execute('''
UPDATE station_record
SET athlete_name = CASE athlete
  WHEN 'self' THEN '我'
  WHEN 'both' THEN '共同完成'
  WHEN 'partner' THEN (
    SELECT partner_name FROM training_session
    WHERE training_session.id = station_record.session_id
  )
  ELSE NULL
END
WHERE athlete IS NOT NULL
''');
        }
        if (oldVersion < 5) {
          if (!await _hasColumn(
            db,
            'training_session',
            'heart_rate_external_id',
          )) {
            await db.execute(
              'ALTER TABLE training_session '
              'ADD COLUMN heart_rate_external_id TEXT',
            );
          }
          if (!await _hasColumn(
            db,
            'training_session',
            'heart_rate_sample_count',
          )) {
            await db.execute(
              'ALTER TABLE training_session '
              'ADD COLUMN heart_rate_sample_count INTEGER',
            );
          }
          if (!await _hasColumn(
            db,
            'training_session',
            'heart_rate_imported_at_ms',
          )) {
            await db.execute(
              'ALTER TABLE training_session '
              'ADD COLUMN heart_rate_imported_at_ms INTEGER',
            );
          }
        }
        if (oldVersion < 6) {
          if (await _hasColumn(
            db,
            'template_segment',
            'distance_meters',
          )) {
            await db.execute('DROP INDEX IF EXISTS idx_template_segment_order');
            await db.execute(
              'ALTER TABLE template_segment RENAME TO template_segment_v5',
            );
            await db.execute(DatabaseSchema.createTemplateSegment);
            await db.execute('''
INSERT INTO template_segment (
  id, template_id, segment_kind, station_type, sequence_index,
  target_distance_meters
)
SELECT id, template_id, 'station', station_type, sequence_index, distance_meters
FROM template_segment_v5
''');
            await db.execute('DROP TABLE template_segment_v5');
            await db.execute(
              'CREATE INDEX idx_template_segment_order '
              'ON template_segment(template_id, sequence_index)',
            );
          }
          if (await _hasColumn(db, 'station_record', 'distance_meters') &&
              !await _hasColumn(
                db,
                'station_record',
                'resistance_level',
              )) {
            await db.execute(
              'ALTER TABLE station_record '
              'ADD COLUMN resistance_level INTEGER',
            );
          }
          await _upgradeBuiltInTemplates(db);
        }
        if (oldVersion < 7) {
          if (!await _hasColumn(
            db,
            'station_record',
            'transition_started_at_ms',
          )) {
            await db.execute(
              'ALTER TABLE station_record '
              'ADD COLUMN transition_started_at_ms INTEGER',
            );
          }
          if (!await _hasColumn(
            db,
            'station_record',
            'transition_ended_at_ms',
          )) {
            await db.execute(
              'ALTER TABLE station_record '
              'ADD COLUMN transition_ended_at_ms INTEGER',
            );
          }
          if (!await _hasColumn(
            db,
            'station_record',
            'transition_duration_ms',
          )) {
            await db.execute(
              'ALTER TABLE station_record '
              'ADD COLUMN transition_duration_ms INTEGER',
            );
          }
        }
        if (oldVersion < 8) {
          if (!await _hasColumn(
            db,
            'training_template',
            'template_type',
          )) {
            await db.execute(
              'ALTER TABLE training_template ADD COLUMN template_type TEXT '
              "NOT NULL DEFAULT 'other'",
            );
          }
          await db.update(
            'training_template',
            {'template_type': 'hyrox_race'},
            where: 'is_built_in = 1',
          );

          if (await _hasColumn(
            db,
            'template_segment',
            'distance_meters',
          )) {
            await db.execute('DROP INDEX IF EXISTS idx_template_segment_order');
            await db.execute(
              'ALTER TABLE template_segment RENAME TO template_segment_v7',
            );
            await db.execute(DatabaseSchema.createTemplateSegment);
            await db.execute('''
INSERT INTO template_segment (
  id, template_id, segment_kind, station_type, sequence_index,
  target_distance_meters, target_resistance_level,
  target_weight_kg, target_repetitions
)
SELECT
  id, template_id, 'station', station_type, sequence_index,
  distance_meters, resistance_level, weight_kg, repetitions
FROM template_segment_v7
''');
            await db.execute('DROP TABLE template_segment_v7');
            await db.execute(
              'CREATE INDEX idx_template_segment_order '
              'ON template_segment(template_id, sequence_index)',
            );
          }

          if (await _hasColumn(db, 'station_record', 'distance_meters')) {
            await db.execute('DROP INDEX IF EXISTS idx_station_session');
            await db.execute(
              'ALTER TABLE station_record RENAME TO station_record_v7',
            );
            await db.execute(DatabaseSchema.createStationRecord);
            await db.execute('''
INSERT INTO station_record (
  id, session_id, segment_kind, station_type, run_number, sequence_index,
  status, started_at_ms, ended_at_ms, duration_ms, accumulated_ms,
  athlete, athlete_name, target_distance_meters,
  target_resistance_level, target_weight_kg, target_repetitions,
  transition_started_at_ms, transition_ended_at_ms,
  transition_duration_ms, remark
)
SELECT
  id, session_id, 'station', station_type, run_number, sequence_index,
  status, started_at_ms, ended_at_ms, duration_ms, accumulated_ms,
  athlete, athlete_name, distance_meters, resistance_level, weight_kg,
  repetitions, transition_started_at_ms, transition_ended_at_ms,
  transition_duration_ms, remark
FROM station_record_v7
''');
            await db.execute('DROP TABLE station_record_v7');
            await db.execute(
              'CREATE INDEX idx_station_session '
              'ON station_record(session_id, sequence_index)',
            );
          }

          await db.execute(DatabaseSchema.createHeartRateImport);
          await db.execute('''
INSERT INTO heart_rate_import (
  session_id, source, external_activity_id, imported_at_ms,
  sample_count, avg_heart_rate, max_heart_rate, is_active
)
SELECT
  sample.session_id,
  MIN(sample.source),
  session.heart_rate_external_id,
  COALESCE(session.heart_rate_imported_at_ms, session.updated_at_ms),
  COUNT(*),
  CAST(ROUND(AVG(sample.heart_rate_bpm)) AS INTEGER),
  MAX(sample.heart_rate_bpm),
  1
FROM heart_rate_sample sample
JOIN training_session session ON session.id = sample.session_id
GROUP BY sample.session_id
''');
          await db.execute('DROP INDEX IF EXISTS idx_hr_session_time');
          await db.execute(
            'ALTER TABLE heart_rate_sample RENAME TO heart_rate_sample_v7',
          );
          await db.execute(DatabaseSchema.createHeartRateSample);
          await db.execute('''
INSERT INTO heart_rate_sample (
  id, session_id, import_batch_id, timestamp_ms,
  heart_rate_bpm, speed_mps, cadence_rpm
)
SELECT
  sample.id, sample.session_id, import_batch.id, sample.timestamp_ms,
  sample.heart_rate_bpm, sample.speed_mps, sample.cadence_rpm
FROM heart_rate_sample_v7 sample
JOIN heart_rate_import import_batch
  ON import_batch.session_id = sample.session_id
 AND import_batch.is_active = 1
''');
          await db.execute('DROP TABLE heart_rate_sample_v7');
          await db.execute(
            'CREATE INDEX idx_hr_session_time '
            'ON heart_rate_sample(session_id, timestamp_ms)',
          );
          await db.execute(
            'CREATE INDEX idx_hr_import_session '
            'ON heart_rate_import(session_id, imported_at_ms DESC)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX idx_active_hr_import '
            'ON heart_rate_import(session_id) WHERE is_active = 1',
          );
        }
        if (oldVersion < 9) {
          if (!await _hasColumn(
            db,
            'station_record',
            'planned_sequence_index',
          )) {
            await db.execute(
              'ALTER TABLE station_record '
              'ADD COLUMN planned_sequence_index INTEGER',
            );
          }
          if (!await _hasColumn(db, 'station_record', 'origin')) {
            await db.execute(
              'ALTER TABLE station_record ADD COLUMN origin TEXT '
              "NOT NULL DEFAULT 'template'",
            );
          }
          if (!await _hasColumn(db, 'station_record', 'skip_reason')) {
            await db.execute(
              'ALTER TABLE station_record ADD COLUMN skip_reason TEXT',
            );
          }
          await db.execute('''
UPDATE station_record
SET planned_sequence_index = sequence_index
WHERE planned_sequence_index IS NULL AND origin = 'template'
''');
        }
        if (oldVersion < 10) {
          if (!await _hasColumn(
            db,
            'training_session',
            'perceived_effort',
          )) {
            await db.execute(
              'ALTER TABLE training_session ADD COLUMN perceived_effort '
              'INTEGER CHECK(perceived_effort IS NULL OR '
              'perceived_effort BETWEEN 1 AND 10)',
            );
          }
          if (!await _hasColumn(db, 'training_session', 'feeling')) {
            await db.execute(
              "ALTER TABLE training_session ADD COLUMN feeling TEXT "
              "CHECK(feeling IS NULL OR feeling IN "
              "('very_bad', 'bad', 'neutral', 'good', 'very_good'))",
            );
          }
        }
      },
    );
  }

  Future<int> _seedStandardTemplate(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final templateId = await db.insert('training_template', {
      'name': '标准 HYROX 模拟',
      'template_type': 'hyrox_race',
      'is_built_in': 1,
      'created_at_ms': now,
      'updated_at_ms': now,
    });
    for (var index = 0;
        index < DatabaseSchema.standardTemplateSegments.length;
        index++) {
      final segment = DatabaseSchema.standardTemplateSegments[index];
      await db.insert('template_segment', {
        'template_id': templateId,
        'station_type': segment.type,
        'sequence_index': index,
        'target_distance_meters': segment.distance,
      });
    }
    return templateId;
  }

  Future<void> _seedBuiltInTemplates(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final definition in DatabaseSchema.builtInTemplates) {
      final templateId = await db.insert('training_template', {
        'name': definition.name,
        'template_type': 'hyrox_race',
        'is_built_in': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      await _insertBuiltInSegments(db, templateId, definition);
    }
  }

  Future<void> _upgradeBuiltInTemplates(DatabaseExecutor db) async {
    final definitions = DatabaseSchema.builtInTemplates;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final builtIns = await db.query(
      'training_template',
      where: 'is_built_in = 1',
      orderBy: 'id ASC',
    );

    final menOpen = definitions.first;
    final existingMenOpen = builtIns.where(
      (row) => row['name'] == menOpen.name,
    );
    final legacy = builtIns.where(
      (row) => row['name'] == '标准 HYROX 模拟',
    );
    final menOpenId = existingMenOpen.isNotEmpty
        ? existingMenOpen.first['id']! as int
        : legacy.isNotEmpty
            ? legacy.first['id']! as int
            : builtIns.isNotEmpty
                ? builtIns.first['id']! as int
                : await db.insert('training_template', {
                    'name': menOpen.name,
                    'template_type': 'hyrox_race',
                    'is_built_in': 1,
                    'created_at_ms': now,
                    'updated_at_ms': now,
                  });
    await db.update(
      'training_template',
      {
        'name': menOpen.name,
        'template_type': 'hyrox_race',
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [menOpenId],
    );
    await _replaceBuiltInSegments(db, menOpenId, menOpen);

    for (final definition in definitions.skip(1)) {
      final existing = builtIns.where((row) => row['name'] == definition.name);
      final templateId = existing.isNotEmpty
          ? existing.first['id']! as int
          : await db.insert('training_template', {
              'name': definition.name,
              'template_type': 'hyrox_race',
              'is_built_in': 1,
              'created_at_ms': now,
              'updated_at_ms': now,
            });
      await _replaceBuiltInSegments(db, templateId, definition);
    }
  }

  Future<void> _replaceBuiltInSegments(
    DatabaseExecutor db,
    int templateId,
    BuiltInTemplateDefinition definition,
  ) async {
    await db.delete(
      'template_segment',
      where: 'template_id = ?',
      whereArgs: [templateId],
    );
    await _insertBuiltInSegments(db, templateId, definition);
  }

  Future<void> _insertBuiltInSegments(
    DatabaseExecutor db,
    int templateId,
    BuiltInTemplateDefinition definition,
  ) async {
    for (var index = 0; index < definition.segments.length; index++) {
      final segment = definition.segments[index];
      await db.insert('template_segment', {
        'template_id': templateId,
        'station_type': segment.type,
        'segment_kind': 'station',
        'sequence_index': index,
        'target_distance_meters': segment.distanceMeters,
        'target_resistance_level': segment.resistanceLevel,
        'target_weight_kg': segment.weightKg,
        'target_repetitions': segment.repetitions,
      });
    }
  }

  Future<bool> _hasColumn(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }
}
