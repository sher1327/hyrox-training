import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../heart_rate/presentation/controllers/live_heart_rate_controller.dart';
import '../../../heart_rate/presentation/widgets/live_heart_rate_card.dart';
import '../../domain/models/training_models.dart';
import '../controllers/training_timer_controller.dart';
import '../formatters/training_formatters.dart';
import '../widgets/station_actual_editor.dart';
import '../widgets/training_queue_sheet.dart';
import '../widgets/running_lap_distance_editor.dart';

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
    ref.watch(liveHeartRateControllerProvider(sessionId));
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
              tooltip: '实时心率带',
              onPressed: timer.valueOrNull == null
                  ? null
                  : () => showLiveHeartRateSheet(
                        context: context,
                        sessionId: sessionId,
                      ),
              icon: const Icon(Icons.favorite_outline_rounded),
            ),
            IconButton(
              tooltip: '训练队列',
              onPressed: timer.valueOrNull == null ? null : _openTrainingQueue,
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
                  onFinish: _finishAfterTransition,
                  onAdjustNext: _openTrainingQueue,
                  onEditActual: () => _editActual(value.transitionSource!),
                  onUndoCompletion: () => _confirmUndoCompletion(value),
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
                    const SizedBox(height: 10),
                    LiveHeartRateCard(sessionId: sessionId),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              '当前项目 ${value.currentOrdinal}/'
                              '${value.executableStations.length}',
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
                            if (current.type == StationType.run) ...[
                              const SizedBox(height: 10),
                              Text(
                                '当前分段 '
                                '${formatDuration(value.currentLapElapsed, includeHours: false)}'
                                ' · 已记录 ${value.currentRunningLaps.length} 段',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ProgressDots(stations: value.stations),
                    if (value.nextPending != null) ...[
                      const SizedBox(height: 12),
                      _NextStationCard(
                        station: value.nextPending!,
                        onAdjust: value.isSaving ? null : _openTrainingQueue,
                      ),
                    ],
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
                    if (value.undoCandidate != null) ...[
                      TextButton.icon(
                        onPressed: value.isSaving
                            ? null
                            : () => _confirmUndoCompletion(value),
                        icon: const Icon(Icons.undo_rounded),
                        label: Text(
                          '撤销上次完成：${value.undoCandidate!.displayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (current.type == StationType.run) ...[
                      OutlinedButton.icon(
                        onPressed: value.isSaving ? null : _recordRunningLap,
                        icon: const Icon(Icons.flag_rounded),
                        label: const Text('记录跑步分段'),
                      ),
                      const SizedBox(height: 10),
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
      if (done && mounted) await _finishHeartRateAndShowReport();
    } catch (error) {
      _showError('完成项目失败：$error');
    }
  }

  Future<void> _recordRunningLap() async {
    try {
      final lap = await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .recordRunningLap();
      if (lap == null || !mounted) return;
      final edit = await showRunningLapDistanceEditor(
        context,
        lapNumber: lap.sequenceIndex + 1,
      );
      if (!mounted) return;
      if (edit == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('第 ${lap.sequenceIndex + 1} 段已记录')),
        );
        return;
      }
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .updateRunningLapDistance(lap.id, edit.distanceMeters);
    } catch (error) {
      _showError('记录跑步分段失败：$error');
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

  Future<void> _finishAfterTransition() async {
    try {
      final done = await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .finishAfterTransition();
      if (done && mounted) await _finishHeartRateAndShowReport();
    } catch (error) {
      _showError('结束训练失败：$error');
    }
  }

  Future<void> _openTrainingQueue() => showTrainingQueueSheet(
        context: context,
        sessionId: sessionId,
      );

  Future<void> _editActual(StationRecord station) async {
    final actual = await showStationActualEditor(context, station);
    if (actual == null || !mounted) return;
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .updateActualPerformance(station.id, actual);
    } catch (error) {
      _showError('保存实际数据失败：$error');
    }
  }

  Future<void> _confirmUndoCompletion(TrainingTimerState value) async {
    final candidate = value.undoCandidate;
    if (candidate == null) return;
    final activeNext = value.current;
    final nextElapsed = activeNext?.startedAt == null
        ? Duration.zero
        : value.now.difference(activeNext!.startedAt!);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('返回上一项目继续计时？'),
        content: Text(
          activeNext == null
              ? '将撤销“${candidate.displayName}”的完成记录和本次转换计时。'
                  '项目会从原开始时间继续计时。'
              : '当前“${activeNext.displayName}”已计时 '
                  '${formatDuration(nextElapsed, includeHours: false)}。\n\n'
                  '确认后会清除这段误计时间，并返回“${candidate.displayName}”'
                  '从原开始时间继续计时。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保持当前项目'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认返回'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .undoLastCompletion();
    } catch (error) {
      _showError('撤销完成失败：$error');
    }
  }

  Future<bool?> _chooseNextStep(TrainingTimerState value) async {
    final current = value.current;
    if (current == null) return null;
    if (value.nextPending == null) return false;
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
      await ref
          .read(liveHeartRateControllerProvider(sessionId).notifier)
          .stopRecording();
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
      if (done && mounted) await _finishHeartRateAndShowReport();
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

  Future<void> _finishHeartRateAndShowReport() async {
    await ref
        .read(liveHeartRateControllerProvider(sessionId).notifier)
        .stopRecording();
    if (mounted) _showCompletedReport();
  }

  void _showCompletedReport() {
    context.go('/training/$sessionId?source=training_completed');
  }
}

class _TransitionTimerBody extends StatelessWidget {
  const _TransitionTimerBody({
    required this.state,
    required this.onStartNext,
    required this.onFinish,
    required this.onAdjustNext,
    required this.onEditActual,
    required this.onUndoCompletion,
  });

  final TrainingTimerState state;
  final Future<void> Function() onStartNext;
  final Future<void> Function() onFinish;
  final Future<void> Function() onAdjustNext;
  final Future<void> Function() onEditActual;
  final Future<void> Function() onUndoCompletion;

  @override
  Widget build(BuildContext context) {
    final source = state.transitionSource!;
    final next = state.nextAfterTransition;
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
                      '${source.displayName}\n→ '
                      '${next?.displayName ?? '没有待进行项目'}',
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
            TextButton.icon(
              onPressed: state.isSaving ? null : onUndoCompletion,
              icon: const Icon(Icons.undo_rounded),
              label: Text('撤销完成，继续 ${source.displayName}'),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: state.isSaving ? null : onEditActual,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('修改上一项实际完成数据'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: state.isSaving ? null : onAdjustNext,
              icon: const Icon(Icons.swap_vert_rounded),
              label: const Text('调整下一项'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: state.isSaving
                  ? null
                  : next == null
                      ? onFinish
                      : onStartNext,
              icon: Icon(
                next == null
                    ? Icons.flag_circle_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: Text(
                state.isSaving
                    ? '保存中…'
                    : next == null
                        ? '结束训练'
                        : '开始 ${next.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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

class _NextStationCard extends StatelessWidget {
  const _NextStationCard({required this.station, required this.onAdjust});

  final StationRecord station;
  final VoidCallback? onAdjust;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white.withValues(alpha: 0.04),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.next_plan_outlined),
          title: const Text(
            '下一项',
            style: TextStyle(color: Colors.white54),
          ),
          subtitle: Text(
            station.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: TextButton(
            onPressed: onAdjust,
            child: const Text('调整'),
          ),
        ),
      );
}
