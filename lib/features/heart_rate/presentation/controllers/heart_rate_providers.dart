import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../training/domain/models/training_models.dart';
import '../../../training/presentation/controllers/training_providers.dart';
import '../../data/dao/heart_rate_dao.dart';
import '../../data/repositories/sqlite_heart_rate_repository.dart';
import '../../data/services/fit_heart_rate_parser.dart';
import '../../data/services/intervals_credentials_store.dart';
import '../../data/services/intervals_icu_client.dart';
import '../../domain/models/heart_rate_models.dart';
import '../../domain/repositories/heart_rate_repository.dart';
import '../../domain/services/heart_rate_import_service.dart';

final heartRateRepositoryFutureProvider =
    FutureProvider<HeartRateRepository>((ref) async {
  final db = await AppDatabase.instance.database;
  return SqliteHeartRateRepository(HeartRateDao(db));
});

final intervalsCredentialsStoreProvider = Provider<IntervalsCredentialsStore>(
  (ref) => IntervalsCredentialsStore(),
);

final intervalsIcuClientProvider = Provider<IntervalsIcuClient>(
  (ref) => IntervalsIcuClient(),
);

final fitHeartRateParserProvider = Provider<FitHeartRateParser>(
  (ref) => const FitHeartRateParser(),
);

final heartRateImportServiceFutureProvider =
    FutureProvider<HeartRateImportService>((ref) async {
  final repository = await ref.watch(heartRateRepositoryFutureProvider.future);
  return HeartRateImportService(
    repository: repository,
    intervalsClient: ref.watch(intervalsIcuClientProvider),
  );
});

final heartRateAnalysisProvider = FutureProvider.autoDispose
    .family<HeartRateAnalysis, int>((ref, sessionId) async {
  final heartRateRepository =
      await ref.watch(heartRateRepositoryFutureProvider.future);
  final trainingRepository =
      await ref.watch(trainingRepositoryFutureProvider.future);
  final values = await Future.wait([
    heartRateRepository.listSamples(sessionId),
    trainingRepository.listStations(sessionId),
  ]);
  return HeartRateAnalysis.build(
    values[0] as List<HeartRateSample>,
    values[1] as List<StationRecord>,
  );
});

final heartRateSourcesProvider = FutureProvider.autoDispose
    .family<List<HeartRateSourceData>, int>((ref, sessionId) async {
  final repository =
      await ref.watch(heartRateRepositoryFutureProvider.future);
  final batches = await repository.listBatches(sessionId);
  return Future.wait(
    batches.map(
      (batch) async => HeartRateSourceData(
        batch: batch,
        samples: await repository.listSamplesByBatch(batch.id),
      ),
    ),
  );
});

final heartRateImportingProvider =
    StateProvider.autoDispose.family<bool, int>((ref, sessionId) => false);
