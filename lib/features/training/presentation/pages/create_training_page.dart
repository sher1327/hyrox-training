import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/training_models.dart';
import '../../domain/models/training_exceptions.dart';
import '../../domain/models/training_template.dart';
import '../controllers/training_providers.dart';

class CreateTrainingPage extends ConsumerStatefulWidget {
  const CreateTrainingPage({super.key});

  @override
  ConsumerState<CreateTrainingPage> createState() => _CreateTrainingPageState();
}

class _CreateTrainingPageState extends ConsumerState<CreateTrainingPage> {
  TrainingMode _mode = TrainingMode.single;
  final _teammateControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );
  int? _selectedTemplateId;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _teammateControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final teammateCount = switch (_mode) {
      TrainingMode.single => 0,
      TrainingMode.double => 1,
      TrainingMode.relay => 3,
    };
    final teammateNames = _teammateControllers
        .take(teammateCount)
        .map((controller) => controller.text.trim())
        .toList();
    if (teammateNames.any((name) => name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode == TrainingMode.relay ? '接力模式请填写三名队友的姓名' : '双人模式请填写队友姓名',
          ),
        ),
      );
      return;
    }
    if (teammateNames.toSet().length != teammateNames.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('队友姓名不能重复')),
      );
      return;
    }
    if (teammateNames.any((name) => name == '我' || name == '共同完成')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('“我”和“共同完成”是系统保留名称')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repository =
          await ref.read(trainingRepositoryFutureProvider.future);
      final activeSession = await repository.getActiveSession();
      if (activeSession != null) {
        if (mounted) {
          setState(() => _saving = false);
          await _showActiveTraining(activeSession.id);
        }
        return;
      }
      final templateRepository =
          await ref.read(trainingTemplateRepositoryFutureProvider.future);
      final templates = await templateRepository.listTemplates();
      if (templates.isEmpty) throw StateError('没有可用的训练模板');
      final template = templates.firstWhere(
        (item) => item.id == _selectedTemplateId,
        orElse: () => templates.first,
      );
      final now = ref.read(clockProvider).now();
      final id = await repository.createAndStartSession(
        mode: _mode,
        title: template.name,
        template: template,
        teammateNames: teammateNames,
        startedAt: now,
      );
      ref.invalidate(trainingSessionsProvider);
      if (mounted) context.go('/training/$id/live');
    } on ActiveTrainingExistsException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _showActiveTraining(error.sessionId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建训练失败：$error')),
      );
    }
  }

  Future<void> _showActiveTraining(int sessionId) async {
    final continueTraining = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('已有训练正在进行'),
        content: const Text('同一时间只能进行一场训练。你可以返回并继续之前的训练。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('留在这里'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续原训练'),
          ),
        ],
      ),
    );
    if (continueTraining == true && mounted) {
      context.go('/training/$sessionId/live');
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(trainingTemplatesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建训练'),
        actions: [
          TextButton(
            onPressed: () => context.push('/templates'),
            child: const Text('管理模板'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('训练模板', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            templates.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => ListTile(
                title: Text('模板读取失败：$error'),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(trainingTemplatesProvider),
                  child: const Text('重试'),
                ),
              ),
              data: (items) {
                if (items.isEmpty) return const Text('暂无训练模板');
                final selected = items.where(
                  (item) => item.id == _selectedTemplateId,
                );
                final template =
                    selected.isEmpty ? items.first : selected.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: template.id,
                          items: items
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(item.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedTemplateId = value),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TemplatePreview(template: template),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('训练模式', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SegmentedButton<TrainingMode>(
              segments: const [
                ButtonSegment(value: TrainingMode.single, label: Text('单人')),
                ButtonSegment(value: TrainingMode.double, label: Text('双人')),
                ButtonSegment(value: TrainingMode.relay, label: Text('接力')),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            if (_mode != TrainingMode.single) ...[
              const SizedBox(height: 20),
              for (var index = 0;
                  index < (_mode == TrainingMode.relay ? 3 : 1);
                  index++) ...[
                TextField(
                  controller: _teammateControllers[index],
                  textInputAction: _mode == TrainingMode.relay && index < 2
                      ? TextInputAction.next
                      : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: _mode == TrainingMode.relay
                        ? '队友 ${index + 1} 姓名'
                        : '队友姓名',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (index < (_mode == TrainingMode.relay ? 2 : 0))
                  const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  _saving || templates.valueOrNull == null ? null : _start,
              child: Text(_saving ? '创建中…' : '开始训练'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({required this.template});

  final TrainingTemplate template;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${template.segments.length} 个计时项目'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: template.segments
                    .map(
                      (segment) => Chip(
                        label: Text(segment.displayName),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      );
}
