import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/time/clock.dart';
import '../../data/dao/training_dao.dart';
import '../../data/dao/training_template_dao.dart';
import '../../data/repositories/sqlite_training_repository.dart';
import '../../data/repositories/sqlite_training_template_repository.dart';
import '../../domain/repositories/training_repository.dart';
import '../../domain/repositories/training_template_repository.dart';
import '../../domain/models/training_template.dart';
import '../../domain/models/training_models.dart';
import '../../domain/models/training_report.dart';

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final trainingRepositoryFutureProvider =
    FutureProvider<TrainingRepository>((ref) async {
  final db = await AppDatabase.instance.database;
  return SqliteTrainingRepository(TrainingDao(db));
});

final trainingTemplateRepositoryFutureProvider =
    FutureProvider<TrainingTemplateRepository>((ref) async {
  final db = await AppDatabase.instance.database;
  return SqliteTrainingTemplateRepository(TrainingTemplateDao(db));
});

final trainingTemplatesProvider =
    FutureProvider.autoDispose<List<TrainingTemplate>>((ref) async {
  final repository =
      await ref.watch(trainingTemplateRepositoryFutureProvider.future);
  return repository.listTemplates();
});

final trainingSessionsProvider =
    FutureProvider.autoDispose<List<TrainingSession>>((ref) async {
  final repository = await ref.watch(trainingRepositoryFutureProvider.future);
  return repository.listSessions();
});

final trainingReportProvider = FutureProvider.autoDispose
    .family<TrainingReport?, int>((ref, sessionId) async {
  final repository = await ref.watch(trainingRepositoryFutureProvider.future);
  final session = await repository.getSession(sessionId);
  if (session == null) return null;
  final values = await Future.wait([
    repository.listStations(sessionId),
    repository.listRunningLaps(sessionId),
  ]);
  return TrainingReport.build(
    session,
    values[0] as List<StationRecord>,
    values[1] as List<RunningLap>,
  );
});
