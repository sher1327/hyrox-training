import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_schema.dart';
import '../../domain/models/database_backup.dart';

final class DatabaseBackupService {
  DatabaseBackupService(this._appDatabase);

  final AppDatabase _appDatabase;
  bool _busy = false;

  static const _baseRequiredTables = {
    'training_template',
    'template_segment',
    'training_session',
    'station_record',
    'heart_rate_import',
    'heart_rate_sample',
  };

  Future<DatabaseBackupSummary> currentSummary() async {
    await _appDatabase.prepareForSnapshot();
    return inspect(await _appDatabase.databasePath);
  }

  Future<DateTime?> lastExternalBackupAt() async {
    final marker = File(await _externalBackupMarkerPath());
    if (!await marker.exists()) return null;
    final value = int.tryParse(await marker.readAsString());
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  Future<void> markExternalBackupCreated(DateTime at) async {
    final marker = File(await _externalBackupMarkerPath());
    await marker.parent.create(recursive: true);
    await marker.writeAsString('${at.toUtc().millisecondsSinceEpoch}');
  }

  Future<BackupSnapshot> createExportSnapshot() => _exclusive(() async {
        final directory = await _workingDirectory();
        final path = p.join(
          directory.path,
          'export_${DateTime.now().toUtc().microsecondsSinceEpoch}.hyroxbackup',
        );
        return _createSnapshotAt(path);
      });

  Future<BackupSnapshot> createInternalSnapshot({required String reason}) =>
      _exclusive(() async {
        final directory = await _internalBackupDirectory();
        final safeReason = reason.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
        final path = p.join(
          directory.path,
          'auto_${_fileTimestamp(DateTime.now())}_$safeReason.hyroxbackup',
        );
        final snapshot = await _createSnapshotAt(path);
        await _pruneInternalSnapshots(directory, keep: 5);
        return snapshot;
      });

  Future<List<DatabaseBackupSummary>> listInternalSnapshots() async {
    final directory = await _internalBackupDirectory();
    final files = await directory
        .list()
        .where(
            (entity) => entity is File && entity.path.endsWith('.hyroxbackup'))
        .cast<File>()
        .toList();
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    final summaries = <DatabaseBackupSummary>[];
    for (final file in files) {
      try {
        summaries.add(await inspect(file.path));
      } on DatabaseBackupException {
        // Ignore a partial snapshot; valid snapshots remain available.
      }
    }
    return summaries;
  }

  Future<DatabaseBackupSummary> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const DatabaseBackupException('备份文件不存在');
    }
    final length = await file.length();
    if (length < 100) {
      throw const DatabaseBackupException('文件过小，不是有效的 HYROX 备份');
    }
    final header = await file.openRead(0, 16).fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    if (utf8.decode(header, allowMalformed: true) != 'SQLite format 3\u0000') {
      throw const DatabaseBackupException('文件格式不正确，请选择 .hyroxbackup 文件');
    }

    Database? backup;
    try {
      backup = await openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );
      final integrity = await backup.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw const DatabaseBackupException('备份数据库完整性校验失败');
      }
      final version = await backup.getVersion();
      if (version <= 0) {
        throw const DatabaseBackupException('备份缺少数据库版本信息');
      }
      if (version > DatabaseSchema.version) {
        throw DatabaseBackupException(
          '备份来自更新版本的 App（数据库 v$version），当前版本无法安全恢复',
        );
      }
      final tableRows = await backup.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = tableRows.map((row) => row['name'] as String).toSet();
      final requiredTables = {
        ..._baseRequiredTables,
        if (version >= 11) ...{
          'concept2_result',
          'concept2_interval',
        },
        if (version >= 12) 'concept2_stroke',
        if (version >= 13) 'running_lap',
      };
      final missing = requiredTables.difference(tables);
      if (missing.isNotEmpty) {
        throw DatabaseBackupException('备份缺少必要数据表：${missing.join(', ')}');
      }
      final stat = await file.stat();
      return DatabaseBackupSummary(
        path: path,
        fileName: p.basename(path),
        fileSizeBytes: length,
        databaseVersion: version,
        modifiedAt: stat.modified.toUtc(),
        trainingCount: await _count(backup, 'training_session'),
        customTemplateCount: await _count(
          backup,
          'training_template',
          where: 'is_built_in = 0',
        ),
        stationRecordCount: await _count(backup, 'station_record'),
        heartRateSampleCount: await _count(backup, 'heart_rate_sample'),
        activeTrainingCount: await _count(
          backup,
          'training_session',
          where: "status = 'in_progress'",
        ),
        sha256: (await sha256.bind(file.openRead()).first).toString(),
      );
    } on DatabaseBackupException {
      rethrow;
    } on DatabaseException catch (error) {
      throw DatabaseBackupException('无法读取备份数据库：$error');
    } finally {
      await backup?.close();
    }
  }

  Future<DatabaseRestoreResult> restore(String sourcePath) =>
      _exclusive(() async {
        await inspect(sourcePath);
        final current = await currentSummary();
        if (current.activeTrainingCount > 0) {
          throw const DatabaseBackupException('当前有正在进行的训练，请先完成或取消后再恢复');
        }

        final databasePath = await _appDatabase.databasePath;
        final databaseFile = File(databasePath);
        final staged = File('$databasePath.restore_staged');
        final rollback = File('$databasePath.restore_rollback');
        if (await staged.exists()) await staged.delete();
        if (await rollback.exists()) await rollback.delete();
        await File(sourcePath).copy(staged.path);

        final safetyDirectory = await _internalBackupDirectory();
        final safetyPath = p.join(
          safetyDirectory.path,
          'auto_${_fileTimestamp(DateTime.now())}_before_restore.hyroxbackup',
        );
        final safety = await _createSnapshotAt(safetyPath);
        await _pruneInternalSnapshots(safetyDirectory, keep: 5);

        var movedCurrent = false;
        try {
          await _appDatabase.close();
          await _deleteSidecars(databasePath);
          if (await databaseFile.exists()) {
            await databaseFile.rename(rollback.path);
            movedCurrent = true;
          }
          await staged.rename(databasePath);
          await _appDatabase.reopen();
          await _appDatabase.prepareForSnapshot();
          final restored = await inspect(databasePath);
          if (await rollback.exists()) await rollback.delete();
          return DatabaseRestoreResult(
            restored: restored,
            safetySnapshotPath: safety.path,
          );
        } catch (error) {
          await _appDatabase.close();
          if (await databaseFile.exists()) await databaseFile.delete();
          if (movedCurrent && await rollback.exists()) {
            await rollback.rename(databasePath);
          }
          await _appDatabase.reopen();
          if (error is DatabaseBackupException) rethrow;
          throw DatabaseBackupException('恢复失败，已回滚到原数据：$error');
        } finally {
          if (await staged.exists()) await staged.delete();
        }
      });

  Future<void> deleteTemporarySnapshot(BackupSnapshot snapshot) async {
    final file = File(snapshot.path);
    if (await file.exists()) await file.delete();
  }

  String suggestedFileName(DateTime now) =>
      'HYROX_Backup_${_fileTimestamp(now)}.hyroxbackup';

  Future<BackupSnapshot> _createSnapshotAt(String targetPath) async {
    await _appDatabase.prepareForSnapshot();
    final source = File(await _appDatabase.databasePath);
    if (!await source.exists()) {
      throw const DatabaseBackupException('本机数据库不存在');
    }
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    if (await target.exists()) await target.delete();
    await source.copy(target.path);
    return BackupSnapshot(
        path: target.path, summary: await inspect(target.path));
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_busy) throw const DatabaseBackupException('已有备份或恢复操作正在进行');
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  Future<int> _count(
    DatabaseExecutor executor,
    String table, {
    String? where,
  }) async {
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS count FROM $table'
      '${where == null ? '' : ' WHERE $where'}',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<Directory> _workingDirectory() async {
    final directory = Directory(
      p.join(p.dirname(await _appDatabase.databasePath), 'backup_work'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _internalBackupDirectory() async {
    final directory = Directory(
      p.join(p.dirname(await _appDatabase.databasePath), 'automatic_backups'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _externalBackupMarkerPath() async => p.join(
        p.dirname(await _appDatabase.databasePath),
        'last_external_backup_ms',
      );

  Future<void> _pruneInternalSnapshots(
    Directory directory, {
    required int keep,
  }) async {
    final files = await directory
        .list()
        .where(
            (entity) => entity is File && entity.path.endsWith('.hyroxbackup'))
        .cast<File>()
        .toList();
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    for (final file in files.skip(keep)) {
      await file.delete();
    }
  }

  Future<void> _deleteSidecars(String databasePath) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final file = File('$databasePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}

String _fileTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}${two(local.month)}${two(local.day)}_'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
}
