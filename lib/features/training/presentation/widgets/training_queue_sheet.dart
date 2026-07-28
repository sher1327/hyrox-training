import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/training_models.dart';
import '../controllers/training_timer_controller.dart';
import 'training_segment_picker.dart';

Future<void> showTrainingQueueSheet({
  required BuildContext context,
  required int sessionId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _TrainingQueueSheet(sessionId: sessionId),
      ),
    );

enum _QueueAction { makeNext, moveToEnd, skip }

class _TrainingQueueSheet extends ConsumerWidget {
  const _TrainingQueueSheet({required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(trainingTimerProvider(sessionId));
    return timer.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('队列读取失败：$error')),
      data: (state) {
        final pending = state.pendingStations;
        final completedCount = state.stations
            .where(
              (item) =>
                  item.status == SegmentStatus.completed ||
                  (item.status == SegmentStatus.skipped &&
                      !item.wasRemovedBeforeStart),
            )
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '训练队列',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          '拖动待进行项目即可改变本次执行顺序',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (state.current != null)
              _LockedStationTile(
                label: '当前计时',
                station: state.current!,
              )
            else if (state.transitionSource != null)
              _LockedStationTile(
                label: '转换中，上一项',
                station: state.transitionSource!,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '待进行 ${pending.length} 项',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '已完成 $completedCount 项',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: pending.isEmpty && state.removedStations.isEmpty
                  ? const Center(
                      child: Text(
                        '没有待进行项目\n仍可添加临时项目',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      buildDefaultDragHandles: false,
                      itemCount: pending.length,
                      footer: _RemovedStations(
                        stations: state.removedStations,
                        disabled: state.isSaving,
                        onRestore: (station) => _restore(
                          context,
                          ref,
                          station,
                          pending.length,
                        ),
                      ),
                      onReorderItem: state.isSaving
                          ? (_, __) {}
                          : (oldIndex, newIndex) {
                              final ids =
                                  pending.map((item) => item.id).toList();
                              final moved = ids.removeAt(oldIndex);
                              ids.insert(newIndex, moved);
                              unawaited(_reorder(context, ref, ids));
                            },
                      itemBuilder: (context, index) {
                        final station = pending[index];
                        return Card(
                          key: ValueKey(station.id),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: StationTypeIcon(type: station.type),
                            title: Text(station.displayName),
                            subtitle: Text(
                              station.isAdHoc
                                  ? index == 0
                                      ? '下一项 · 临时添加'
                                      : '临时添加'
                                  : index == 0
                                      ? '下一项'
                                      : '待进行',
                              style: TextStyle(
                                color: index == 0
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white54,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<_QueueAction>(
                                  enabled: !state.isSaving,
                                  onSelected: (action) => _act(
                                    context,
                                    ref,
                                    station,
                                    index,
                                    pending,
                                    action,
                                  ),
                                  itemBuilder: (context) => [
                                    if (index != 0)
                                      const PopupMenuItem(
                                        value: _QueueAction.makeNext,
                                        child: Text('设为下一项'),
                                      ),
                                    if (index != pending.length - 1)
                                      const PopupMenuItem(
                                        value: _QueueAction.moveToEnd,
                                        child: Text('移到最后'),
                                      ),
                                    const PopupMenuItem(
                                      value: _QueueAction.skip,
                                      child: Text('本次不做'),
                                    ),
                                  ],
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  enabled: !state.isSaving,
                                  child: const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(Icons.drag_handle_rounded),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: state.isSaving ? null : () => _add(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加临时项目'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
  ) async {
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .reorderPendingStations(ids);
    } catch (error) {
      if (context.mounted) _showError(context, '调整顺序失败：$error');
    }
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    StationRecord station,
    int index,
    List<StationRecord> pending,
    _QueueAction action,
  ) async {
    if (action == _QueueAction.skip) {
      await _skip(context, ref, station, index);
      return;
    }
    final ids = pending.map((item) => item.id).toList();
    ids.remove(station.id);
    if (action == _QueueAction.makeNext) {
      ids.insert(0, station.id);
    } else {
      ids.add(station.id);
    }
    await _reorder(context, ref, ids);
  }

  Future<void> _skip(
    BuildContext context,
    WidgetRef ref,
    StationRecord station,
    int pendingIndex,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本次不做这个项目？'),
        content: Text(
          '“${station.displayName}”会退出待训练队列，并在报告中标记为本次跳过。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('本次不做'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .skipPendingStation(station.id, reason: '训练中调整');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${station.displayName} 已标记为本次不做'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => unawaited(
              ref
                  .read(trainingTimerProvider(sessionId).notifier)
                  .restoreSkippedPendingStation(
                    station.id,
                    pendingIndex: pendingIndex,
                  ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) _showError(context, '跳过项目失败：$error');
    }
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    StationRecord station,
    int pendingIndex,
  ) async {
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .restoreSkippedPendingStation(
            station.id,
            pendingIndex: pendingIndex,
          );
    } catch (error) {
      if (context.mounted) _showError(context, '恢复项目失败：$error');
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final segment = await showTrainingSegmentPicker(context);
    if (segment == null || !context.mounted) return;
    final insertAsNext = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(segment.displayName),
              subtitle: const Text('选择加入本次训练的位置'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('添加为下一项'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('添加到队尾'),
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (insertAsNext == null || !context.mounted) return;
    try {
      await ref
          .read(trainingTimerProvider(sessionId).notifier)
          .addPendingStation(segment, insertAsNext: insertAsNext);
    } catch (error) {
      if (context.mounted) _showError(context, '添加项目失败：$error');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LockedStationTile extends StatelessWidget {
  const _LockedStationTile({required this.label, required this.station});

  final String label;
  final StationRecord station;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Card(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          child: ListTile(
            leading: StationTypeIcon(type: station.type),
            title: Text(station.displayName),
            subtitle: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            trailing: const Icon(Icons.lock_outline_rounded, size: 20),
          ),
        ),
      );
}

class _RemovedStations extends StatelessWidget {
  const _RemovedStations({
    required this.stations,
    required this.disabled,
    required this.onRestore,
  });

  final List<StationRecord> stations;
  final bool disabled;
  final ValueChanged<StationRecord> onRestore;

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              '本次不做',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final station in stations)
            Card(
              child: ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: Text(
                  station.displayName,
                  style: const TextStyle(color: Colors.white54),
                ),
                subtitle: Text(station.skipReason ?? '训练中调整'),
                trailing: TextButton(
                  onPressed: disabled ? null : () => onRestore(station),
                  child: const Text('恢复'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
