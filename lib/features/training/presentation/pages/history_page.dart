import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/training_models.dart';
import '../controllers/training_providers.dart';
import '../widgets/session_card.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(trainingSessionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('全部训练')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(trainingSessionsProvider.future),
        child: sessions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 180),
              Text('读取失败：$error', textAlign: TextAlign.center),
              TextButton(
                onPressed: () => ref.invalidate(trainingSessionsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 180),
                    Icon(Icons.history, size: 52, color: Colors.white24),
                    SizedBox(height: 12),
                    Text('暂无训练记录', textAlign: TextAlign.center),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final session = items[index];
                    return SessionCard(
                      session: session,
                      onTap: () {
                        final suffix =
                            session.status == TrainingStatus.inProgress
                                ? '/live'
                                : '';
                        context.push('/training/${session.id}$suffix');
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
