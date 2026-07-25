import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/training_template.dart';
import '../controllers/training_providers.dart';

class TrainingTemplatesPage extends ConsumerWidget {
  const TrainingTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(trainingTemplatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('训练模板')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/templates/new'),
        icon: const Icon(Icons.add),
        label: const Text('新建模板'),
      ),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('模板读取失败：$error'),
              TextButton(
                onPressed: () => ref.invalidate(trainingTemplatesProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final template = items[index];
            return _TemplateCard(
              template: template,
              onEdit: template.isBuiltIn
                  ? null
                  : () => context.push('/templates/${template.id}/edit'),
              onDelete: template.isBuiltIn
                  ? null
                  : () => _delete(context, ref, template),
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TrainingTemplate template,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${template.name}”？'),
        content: const Text('历史训练会保留当时的模板名称和项目记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final repository =
          await ref.read(trainingTemplateRepositoryFutureProvider.future);
      await repository.deleteTemplate(template.id);
      ref.invalidate(trainingTemplatesProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除模板失败：$error')),
      );
    }
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDelete,
  });

  final TrainingTemplate template;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final runs = template.segments.where((item) => item.type.name == 'run');
    final totalMeters = runs.fold<int>(
      0,
      (sum, item) => sum + (item.distanceMeters ?? 0),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.schema_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          template.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (template.isBuiltIn) ...[
                        const SizedBox(width: 8),
                        const Chip(
                          label: Text('内置'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${template.segments.length} 个项目 · '
                    '${runs.length} 段跑步 · $totalMeters m',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            if (!template.isBuiltIn)
              PopupMenuButton<String>(
                onSelected: (value) =>
                    value == 'edit' ? onEdit?.call() : onDelete?.call(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
