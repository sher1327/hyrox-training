import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/dao/concept2_dao.dart';
import '../../data/repositories/sqlite_concept2_repository.dart';
import '../../data/services/concept2_credentials_store.dart';
import '../../data/services/concept2_logbook_client.dart';
import '../../domain/models/concept2_models.dart';
import '../../domain/repositories/concept2_repository.dart';

final concept2ClientProvider =
    Provider<Concept2LogbookClient>((ref) => Concept2LogbookClient());

final concept2CredentialsStoreProvider =
    Provider<Concept2CredentialsStore>((ref) => Concept2CredentialsStore());

final concept2RepositoryFutureProvider =
    FutureProvider<Concept2Repository>((ref) async {
  final db = await AppDatabase.instance.database;
  return SqliteConcept2Repository(Concept2Dao(db));
});

final concept2ResultProvider = FutureProvider.autoDispose
    .family<Concept2Result?, int>((ref, sessionId) async {
  final repository = await ref.watch(concept2RepositoryFutureProvider.future);
  return repository.getForSession(sessionId);
});
