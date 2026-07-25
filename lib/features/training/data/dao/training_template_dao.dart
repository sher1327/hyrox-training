import 'package:sqflite/sqflite.dart';

import '../../domain/models/training_models.dart';
import '../../domain/models/training_template.dart';

final class TrainingTemplateDao {
  const TrainingTemplateDao(this.db);

  final Database db;

  Future<List<Map<String, Object?>>> listTemplates() => db.query(
        'training_template',
        orderBy: 'is_built_in DESC, '
            'CASE WHEN is_built_in = 1 THEN id END ASC, '
            'updated_at_ms DESC, name ASC',
      );

  Future<List<Map<String, Object?>>> getTemplate(int templateId) => db.query(
        'training_template',
        where: 'id = ?',
        whereArgs: [templateId],
        limit: 1,
      );

  Future<List<Map<String, Object?>>> listSegments(int templateId) => db.query(
        'template_segment',
        where: 'template_id = ?',
        whereArgs: [templateId],
        orderBy: 'sequence_index ASC',
      );

  Future<int> createTemplate({
    required String name,
    required List<TemplateSegmentInput> segments,
    required DateTime createdAt,
  }) =>
      db.transaction((txn) async {
        final timestamp = createdAt.millisecondsSinceEpoch;
        final templateId = await txn.insert('training_template', {
          'name': name,
          'is_built_in': 0,
          'created_at_ms': timestamp,
          'updated_at_ms': timestamp,
        });
        await _insertSegments(txn, templateId, segments);
        return templateId;
      });

  Future<void> updateTemplate({
    required int templateId,
    required String name,
    required List<TemplateSegmentInput> segments,
    required DateTime updatedAt,
  }) =>
      db.transaction((txn) async {
        final updated = await txn.update(
          'training_template',
          {
            'name': name,
            'updated_at_ms': updatedAt.millisecondsSinceEpoch,
          },
          where: 'id = ? AND is_built_in = 0',
          whereArgs: [templateId],
        );
        if (updated == 0) throw StateError('内置模板不能修改');
        await txn.delete(
          'template_segment',
          where: 'template_id = ?',
          whereArgs: [templateId],
        );
        await _insertSegments(txn, templateId, segments);
      });

  Future<void> deleteTemplate(int templateId) async {
    final deleted = await db.delete(
      'training_template',
      where: 'id = ? AND is_built_in = 0',
      whereArgs: [templateId],
    );
    if (deleted == 0) throw StateError('内置模板不能删除');
  }

  Future<void> _insertSegments(
    DatabaseExecutor executor,
    int templateId,
    List<TemplateSegmentInput> segments,
  ) async {
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      await executor.insert('template_segment', {
        'template_id': templateId,
        'station_type': _stationTypeToDb(segment.type),
        'sequence_index': index,
        'distance_meters': segment.distanceMeters,
        'resistance_level': segment.resistanceLevel,
        'weight_kg': segment.weightKg,
        'repetitions': segment.repetitions,
      });
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
