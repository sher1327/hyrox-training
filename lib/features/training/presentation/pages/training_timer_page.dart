import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/training_models.dart';
import '../controllers/training_timer_controller.dart';
import '../formatters/training_formatters.dart';

class TrainingTimerPage extends ConsumerStatefulWidget {
  const TrainingTimerPage({required this.sessionId, super.key});

  final int sessionId;

  @override
  ConsumerState<TrainingTimerPage> createState() => _TrainingTimerPageState();
}

class _TrainingTimerPageState extends ConsumerState<TrainingTimerPage> {
  late final AppLifecycleListener _lifecycleListener;

  int get sessionId => widget.sessionId;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!mounted) return;
        ref.read(trainingTimerProvider(sessionId).notifier).syncAfterResume();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(trainingTimerProvider(sessionId));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && (timer.valueOrNull?.hasActiveTimer ?? false)) {
          _confirmLeave();
        } else if (!didPop) {
          context.go('/');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回',
            onPressed: timer.valueOrNull?.hasActiveTimer ?? false
                ? _confirmLeave
                : () => context.go('/'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: timer.valueOrNull == null
              ? const Text('训练中')
              : Text(timer.requireValue.session.title),
          actions: [
            IconButton(
              tooltip: '项目进度',
              onPressed: timer.valueOrNull == null
                  ? null
                  : () => _showProgress(context, timer.requireValue),
              icon: const Icon(Icons.format_list_numbered_rounded),
            ),
            IconButton(
              tooltip: '取消训练',
              onPressed: !(timer.valueOrNull?.hasActiveTimer ?? false) ||
                      (timer.valueOrNull?.isSaving ?? true)
                  ? null
                  : _confirmCancel,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        ),
        body: timer.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败：$error', textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      trainingTimerProvider(sessionId),
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
          data: (value) {
            final current = value.current;
            if (current == null) {
              if (value.isTransitioning) {
                return _TransitionTimerBody(
                  state: value,
                  onStartNext: _startNextAfterTransition,
                );
              }
              return Center(
                child: FilledButton(
                  onPressed: () => context.go('/training/$sessionId'),
                  child: const Text('查看训练报告'),
                ),
              );
            }
            return SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '总时间',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                    Text(
                      formatDuration(value.totalElapsed),
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              '当前项目 ${current.sequenceIndex + 1}/'
                              '${value.stations.length}',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              current.displayName,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              formatDuration(value.segmentElapsed),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineLarge
                                  ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ProgressDots(stations: value.stations),
                    const Spacer(),
                    if (value.session.mode != TrainingMode.single) ...[
                      Text(
                        '完成者',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          '我',
                          ...value.session.teammateNames,
                          '共同完成',
                        ]
                            .map(
                              (name) => ChoiceChip(
                                label: Text(name),
                                selected: value.selectedAthleteName == name,
                                onSelected: (_) => ref
                                    .read(
                                      trainingTimerProvider(sessionId).notifier,
                                    )
                                    .selectAthlete(name),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed:
                          value.isSaving ? null : () => _completeCurrent(value),
                      child: Text(value.isSaving ? '保存中…' : '完成项目'),
                    ),
                    TextButton(
                      onPressed: value.isSaving ? null : _confirmSkip,
                      child: const Text('跳过当前项目'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _completeCurrent(TrainingTimerState value) async {
    final startTransition = await _chooseNextStep(value);
    if (startTransition == null || !mounted) return;
    try {
      final done = await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .completeCurrent(startTransition: startTransition);
      if (done && mounted) _showCompletedReport();
    } catch (error) {
      _showError('完成项目失败：$error');
    }
  }

  Future<void> _startNextAfterTransition() async {
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .startNextAfterTransition();
    } catch (error) {
      _showError('开始下一项失败：$error');
    }
  }

  Future<bool?> _chooseNextStep(TrainingTimerState value) async {
    final current = value.current;
    if (current == null) return null;
    if (current.sequenceIndex >= value.stations.length - 1) return false;
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('接下来怎么计时？'),
              subtitle: Text('转换时间会独立保存在训练报告中'),
            ),
            ListTile(
              leading: const Icon(Icons.sync_alt_rounded),
              title: const Text('进入转换计时'),
              subtitle: const Text('记录移动、器械准备和换项时间'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_rounded),
              title: const Text('直接开始下一项'),
              subtitle: const Text('下一项立即开始计时，不记录转换'),
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('训练仍在进行'),
        content: const Text('返回首页后计时会继续，稍后可以从首页恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续训练'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('返回首页'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) context.go('/');
  }

  Future<void> _confirmCancel() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消本次训练？'),
        content: const Text('已完成的项目会保留在历史记录中，当前项目不会记录完成时间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续训练'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .cancelTraining();
      if (mounted) context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消训练失败：$error')),
      );
    }
  }

  Future<void> _confirmSkip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳过当前项目？'),
        content: const Text('该项目会被标记为已跳过，不记录完成时间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认跳过'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final value = ref.read(trainingTimerProvider(sessionId)).valueOrNull;
    if (value == null || value.current == null) return;
    final startTransition = await _chooseNextStep(value);
    if (startTransition == null || !mounted) return;
    try {
      final done = await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .skipCurrent(startTransition: startTransition);
      if (done && mounted) _showCompletedReport();
    } catch (error) {
      _showError('跳过项目失败：$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showCompletedReport() {
    context.go('/training/$sessionId?source=training_completed');
  }
}

class _TransitionTimerBody extends StatelessWidget {
  const _TransitionTimerBody({
    required this.state,
    required this.onStartNext,
  });

  final TrainingTimerState state;
  final Future<void> Function() onStartNext;

  @override
  Widget build(BuildContext context) {
    final source = state.transitionSource!;
    final next = state.nextAfterTransition!;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '总时间',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
            Text(
              formatDuration(state.totalElapsed),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      '转换计时',
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${source.displayName}\n→ ${next.displayName}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      formatDuration(state.transitionElapsed),
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ProgressDots(stations: state.stations),
            const Spacer(),
            FilledButton.icon(
              onPressed: state.isSaving ? null : onStartNext,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(state.isSaving ? '保存中…' : '开始下一项'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.stations});

  final List<StationRecord> stations;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: stations.map((station) {
          final color = switch (station.status) {
            SegmentStatus.completed => Colors.green,
            SegmentStatus.active => Theme.of(context).colorScheme.primary,
            SegmentStatus.skipped => Colors.orange,
            SegmentStatus.pending => Colors.white24,
          };
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: station.status == SegmentStatus.active ? 18 : 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
          );
        }).toList(),
      );
}

void _showProgress(BuildContext context, TrainingTimerState state) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.9,
        builder: (context, controller) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '项目进度',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: state.stations.length,
                itemBuilder: (context, index) {
                  final station = state.stations[index];
                  final icon = switch (station.status) {
                    SegmentStatus.completed => Icons.check_circle,
                    SegmentStatus.active => Icons.play_circle_fill,
                    SegmentStatus.skipped => Icons.skip_next,
                    SegmentStatus.pending => Icons.circle_outlined,
                  };
                  return ListTile(
                    leading: Icon(
                      icon,
                      color: station.status == SegmentStatus.active
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(station.displayName),
                    subtitle: station.isTransitionActive
                        ? Text(
                            '转换中 ${formatDuration(state.now.difference(station.transitionStartedAt!), includeHours: false)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : station.transitionDuration == null
                            ? null
                            : Text(
                                '转换 ${formatDuration(station.transitionDuration, includeHours: false)}',
                              ),
                    trailing: Text(
                      station.status == SegmentStatus.active
                          ? '进行中'
                          : formatDuration(
                              station.duration,
                              includeHours: false,
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
