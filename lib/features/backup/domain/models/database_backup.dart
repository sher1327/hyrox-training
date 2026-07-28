final class DatabaseBackupSummary {
  const DatabaseBackupSummary({
    required this.path,
    required this.fileName,
    required this.fileSizeBytes,
    required this.databaseVersion,
    required this.modifiedAt,
    required this.trainingCount,
    required this.customTemplateCount,
    required this.stationRecordCount,
    required this.heartRateSampleCount,
    required this.activeTrainingCount,
    required this.sha256,
  });

  final String path;
  final String fileName;
  final int fileSizeBytes;
  final int databaseVersion;
  final DateTime modifiedAt;
  final int trainingCount;
  final int customTemplateCount;
  final int stationRecordCount;
  final int heartRateSampleCount;
  final int activeTrainingCount;
  final String sha256;

  String get readableSize {
    if (fileSizeBytes >= 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (fileSizeBytes >= 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$fileSizeBytes B';
  }
}

final class BackupSnapshot {
  const BackupSnapshot({required this.path, required this.summary});

  final String path;
  final DatabaseBackupSummary summary;
}

final class DatabaseRestoreResult {
  const DatabaseRestoreResult({
    required this.restored,
    required this.safetySnapshotPath,
  });

  final DatabaseBackupSummary restored;
  final String safetySnapshotPath;
}

final class DatabaseBackupException implements Exception {
  const DatabaseBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
