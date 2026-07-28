import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/services/database_backup_service.dart';
import '../../data/services/backup_document_writer.dart';
import '../../domain/models/database_backup.dart';

final databaseBackupServiceProvider = Provider<DatabaseBackupService>(
  (ref) => DatabaseBackupService(AppDatabase.instance),
);

final backupDocumentWriterProvider = Provider<BackupDocumentWriter>(
  (ref) => const BackupDocumentWriter(),
);

final currentDatabaseSummaryProvider =
    FutureProvider.autoDispose<DatabaseBackupSummary>((ref) async {
  return ref.watch(databaseBackupServiceProvider).currentSummary();
});

final lastExternalBackupProvider =
    FutureProvider.autoDispose<DateTime?>((ref) async {
  return ref.watch(databaseBackupServiceProvider).lastExternalBackupAt();
});

final internalBackupSummariesProvider =
    FutureProvider.autoDispose<List<DatabaseBackupSummary>>((ref) async {
  return ref.watch(databaseBackupServiceProvider).listInternalSnapshots();
});
