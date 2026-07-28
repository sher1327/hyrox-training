import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/training_models.dart';
import '../controllers/training_providers.dart';
import '../widgets/session_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(trainingSessionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HYROX',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 4),
        ),
        actions: [
          IconButton(
            tooltip: '数据备份与恢复',
            onPressed: () => context.push('/data-management'),
            icon: const Icon(Icons.storage_rounded),
          ),
          IconButton(
            tooltip: '训练模板',
            onPressed: () => context.push('/templates'),
            icon: const Icon(Icons.schema_outlined),
          ),
          IconButton(
            tooltip: '历史训练',
            onPressed: () => context.push('/history'),
            icon: const Icon(Icons.bar_chart_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(trainingSessionsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text('今日训练', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            _StartTrainingCard(
              onStart: () => context.push('/training/new'),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '最近训练',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/history'),
                  child: const Text('全部'),
                ),
              ],
            ),
            sessions.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _LoadError(
                message: '$error',
                onRetry: () => ref.invalidate(trainingSessionsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const _EmptyHistory();
                }
                return Column(
                  children: items
                      .take(3)
                      .map(
                        (session) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SessionCard(
                            session: session,
                            onTap: () => _openSession(context, session),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

void _openSession(BuildContext context, TrainingSession session) {
  final suffix = session.status == TrainingStatus.inProgress ? '/live' : '';
  context.push('/training/${session.id}$suffix');
}

class _StartTrainingCard extends StatelessWidget {
  const _StartTrainingCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'HYROX 模拟训练',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                '3 套官方规格 · 支持自定义训练模板',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('创建训练'),
              ),
            ],
          ),
        ),
      );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            '还没有训练记录\n完成第一次模拟后会显示在这里',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.6),
          ),
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text('读取训练失败：$message', textAlign: TextAlign.center),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}
