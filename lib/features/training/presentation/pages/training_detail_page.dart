import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../heart_rate/data/services/intervals_icu_client.dart';
import '../../../heart_rate/domain/models/heart_rate_models.dart';
import '../../../heart_rate/domain/models/intervals_models.dart';
import '../../../heart_rate/presentation/controllers/heart_rate_providers.dart';
import '../../../replay/presentation/controllers/training_replay_providers.dart';
import '../../../replay/presentation/services/training_replay_image_exporter.dart';
import '../../domain/models/training_models.dart';
import '../../domain/models/training_report.dart';
import '../controllers/training_providers.dart';
import '../formatters/training_formatters.dart';
import '../widgets/station_actual_editor.dart';
import 'training_segment_breakdown_page.dart';

class TrainingDetailPage extends ConsumerWidget {
  const TrainingDetailPage({
    required this.sessionId,
    this.returnHomeOnBack = false,
    super.key,
  });

  final int sessionId;
  final bool returnHomeOnBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(trainingReportProvider(sessionId));
    final heartRate = ref.watch(heartRateAnalysisProvider(sessionId));
    final importing = ref.watch(heartRateImportingProvider(sessionId));
    final exporting = ref.watch(trainingReplayExportingProvider(sessionId));
    return PopScope(
      canPop: !returnHomeOnBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && returnHomeOnBack) context.go('/');
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回',
            onPressed: () {
              if (returnHomeOnBack) {
                context.go('/');
              } else if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('训练报告'),
          actions: [
            if (importing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: '导入心率',
                onPressed: report.valueOrNull?.session.endedAt == null
                    ? null
                    : () => _showHeartRateImportOptions(
                          context,
                          ref,
                          report.valueOrNull!.session,
                        ),
                icon: const Icon(Icons.monitor_heart_outlined),
              ),
            IconButton(
              tooltip: '删除训练',
              onPressed: report.valueOrNull == null ||
                      report.valueOrNull!.session.status ==
                          TrainingStatus.inProgress
                  ? null
                  : () => _confirmDelete(context, ref),
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: '返回首页',
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_outlined),
            ),
          ],
        ),
        body: report.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('报告读取失败：$error'),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(trainingReportProvider(sessionId)),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
          data: (value) => value == null
              ? const Center(child: Text('训练记录不存在'))
              : _ReportBody(
                  report: value,
                  heartRate: heartRate,
                  importing: importing,
                  exporting: exporting,
                  onImportHeartRate: () =>
                      _showHeartRateImportOptions(context, ref, value.session),
                  onReplay: () => context.push('/training/$sessionId/replay'),
                  onExportReplay: () => _exportReplay(context, ref),
                  onRunningBreakdown: () => context.push(
                    '/training/$sessionId/breakdown/'
                    '${TrainingBreakdownKind.running.routeName}',
                  ),
                  onStationBreakdown: () => context.push(
                    '/training/$sessionId/breakdown/'
                    '${TrainingBreakdownKind.station.routeName}',
                  ),
                  onUndoFinalCompletion: returnHomeOnBack &&
                          value.session.status == TrainingStatus.completed
                      ? () => _undoFinalCompletion(context, ref, value)
                      : null,
                  onEditActual: (station) => _editActual(context, ref, station),
                ),
        ),
      ),
    );
  }

  Future<void> _exportReplay(BuildContext context, WidgetRef ref) async {
    ref.read(trainingReplayExportingProvider(sessionId).notifier).state = true;
    try {
      final replay = await ref.read(trainingReplayProvider(sessionId).future);
      if (replay == null) {
        throw StateError('训练记录不存在');
      }
      if (replay.duration <= Duration.zero) {
        throw StateError('训练时长无效，暂时无法导出');
      }
      if (!context.mounted) return;
      final result = await ref
          .read(trainingReplayImageExporterProvider)
          .exportToGallery(context, replay);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('完整回放已保存到相册：${result.fileName}.png'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：${_friendlyExportError(error)}')),
      );
    } finally {
      if (context.mounted) {
        ref.read(trainingReplayExportingProvider(sessionId).notifier).state =
            false;
      }
    }
  }

  Future<void> _editActual(
    BuildContext context,
    WidgetRef ref,
    StationRecord station,
  ) async {
    final actual = await showStationActualEditor(context, station);
    if (actual == null || !context.mounted) return;
    try {
      final repository =
          await ref.read(trainingRepositoryFutureProvider.future);
      await repository.updateStationActualPerformance(
        stationId: station.id,
        actualPerformance: actual,
      );
      ref.invalidate(trainingReportProvider(sessionId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('实际完成数据已更新')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$error')),
        );
      }
    }
  }

  Future<void> _undoFinalCompletion(
    BuildContext context,
    WidgetRef ref,
    TrainingReport report,
  ) async {
    if (report.stations.isEmpty) return;
    final last = report.stations.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('继续最后一个项目？'),
        content: Text(
          '将撤销“${last.displayName}”的完成记录，并重新打开本次训练。'
          '计时会从该项目原开始时间继续。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留报告'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('返回继续计时'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final repository =
          await ref.read(trainingRepositoryFutureProvider.future);
      await repository.undoLastStationCompletion(
        sessionId: sessionId,
        restoredAt: ref.read(clockProvider).now(),
      );
      ref.invalidate(trainingSessionsProvider);
      ref.invalidate(trainingReportProvider(sessionId));
      ref.invalidate(heartRateAnalysisProvider(sessionId));
      if (context.mounted) context.go('/training/$sessionId/live');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复计时失败：$error')),
        );
      }
    }
  }

  Future<void> _showHeartRateImportOptions(
    BuildContext context,
    WidgetRef ref,
    TrainingSession session,
  ) async {
    if (session.endedAt == null) return;
    final choice = await showModalBottomSheet<_HeartRateImportChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('导入心率'),
              subtitle: Text('新数据会用于当前分析，历史导入批次仍会保留'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('本地 FIT 文件'),
              subtitle: const Text('从手机文件中选择 .fit 文件'),
              onTap: () => Navigator.pop(
                context,
                _HeartRateImportChoice.fit,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('从 Intervals.icu 在线拉取'),
              subtitle: const Text('按训练时间自动匹配当日活动'),
              onTap: () => Navigator.pop(
                context,
                _HeartRateImportChoice.intervalsIcu,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _HeartRateImportChoice.fit:
        await _importFit(context, ref, session);
        break;
      case _HeartRateImportChoice.intervalsIcu:
        await _importIntervals(context, ref, session);
        break;
    }
  }

  Future<void> _importFit(
    BuildContext context,
    WidgetRef ref,
    TrainingSession session,
  ) async {
    const fitType = XTypeGroup(
      label: 'FIT activity',
      extensions: ['fit'],
      mimeTypes: ['application/octet-stream'],
    );
    final file = await openFile(acceptedTypeGroups: const [fitType]);
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    await _runImport(
      context,
      ref,
      () async {
        final samples = await ref.read(fitHeartRateParserProvider).parse(bytes);
        final service =
            await ref.read(heartRateImportServiceFutureProvider.future);
        return service.importFit(
          session: session,
          samples: samples,
          fileName: file.name,
        );
      },
    );
  }

  Future<void> _importIntervals(
    BuildContext context,
    WidgetRef ref,
    TrainingSession session,
  ) async {
    final store = ref.read(intervalsCredentialsStoreProvider);
    var credentials = await store.read();
    if (!context.mounted) return;
    if (credentials != null) {
      final useSaved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('从 Intervals.icu 拉取'),
          content: Text('使用已保存的运动员 ID：${credentials!.athleteId}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('修改配置'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始拉取'),
            ),
          ],
        ),
      );
      if (useSaved == null || !context.mounted) return;
      if (!useSaved) {
        credentials = await _editIntervalsCredentials(context, credentials);
      }
    } else {
      credentials = await _editIntervalsCredentials(context, null);
    }
    if (credentials == null || !context.mounted) return;
    await store.save(credentials);
    if (!context.mounted) return;
    final confirmedCredentials = credentials;
    final activities = await _findIntervalsActivities(
      context,
      ref,
      session,
      confirmedCredentials,
    );
    if (activities == null || !context.mounted) return;
    if (activities.isEmpty) {
      _showError(context, '当日没有找到与这场训练时间重叠且包含心率的活动');
      return;
    }
    final activity = activities.length == 1
        ? activities.single
        : await _chooseIntervalsActivity(context, activities);
    if (activity == null || !context.mounted) return;
    await _runImport(
      context,
      ref,
      () async {
        final service =
            await ref.read(heartRateImportServiceFutureProvider.future);
        return service.importIntervalsActivity(
          session: session,
          credentials: confirmedCredentials,
          activity: activity,
        );
      },
    );
  }

  Future<List<IntervalsActivity>?> _findIntervalsActivities(
    BuildContext context,
    WidgetRef ref,
    TrainingSession session,
    IntervalsCredentials credentials,
  ) async {
    ref.read(heartRateImportingProvider(sessionId).notifier).state = true;
    try {
      final service =
          await ref.read(heartRateImportServiceFutureProvider.future);
      return await service.findIntervalsActivities(
        session: session,
        credentials: credentials,
      );
    } on IntervalsApiException catch (error) {
      if (context.mounted) _showError(context, error.message);
      return null;
    } catch (error) {
      if (context.mounted) _showError(context, _friendlyError(error));
      return null;
    } finally {
      if (context.mounted) {
        ref.read(heartRateImportingProvider(sessionId).notifier).state = false;
      }
    }
  }

  Future<IntervalsActivity?> _chooseIntervalsActivity(
    BuildContext context,
    List<IntervalsActivity> activities,
  ) =>
      showDialog<IntervalsActivity>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择要导入的活动'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: activities.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final activity = activities[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(activity.name),
                    subtitle: Text(
                      '开始：${_formatActivityStart(activity.startedAt)}\n'
                      '时长：${_formatActivityDuration(activity.elapsedTime)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, activity),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );

  Future<IntervalsCredentials?> _editIntervalsCredentials(
    BuildContext context,
    IntervalsCredentials? existing,
  ) async {
    final formKey = GlobalKey<FormState>();
    final athleteController = TextEditingController(
      text: existing?.athleteId ?? '',
    );
    final apiKeyController = TextEditingController();
    final result = await showDialog<IntervalsCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('配置 Intervals.icu'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: athleteController,
                decoration: const InputDecoration(
                  labelText: '运动员 ID',
                  hintText: '例如 i651080',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入运动员 ID' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: apiKeyController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'API 密钥',
                  hintText: existing == null ? null : '留空则继续使用已保存密钥',
                ),
                validator: (value) =>
                    existing == null && (value == null || value.trim().isEmpty)
                        ? '请输入 API 密钥'
                        : null,
              ),
              const SizedBox(height: 12),
              const Text(
                '密钥仅加密保存在当前设备，不会写入训练数据库。',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                IntervalsCredentials(
                  athleteId: athleteController.text.trim(),
                  apiKey: apiKeyController.text.trim().isEmpty
                      ? existing!.apiKey
                      : apiKeyController.text.trim(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    athleteController.dispose();
    apiKeyController.dispose();
    return result;
  }

  Future<void> _runImport(
    BuildContext context,
    WidgetRef ref,
    Future<HeartRateImportResult> Function() action,
  ) async {
    ref.read(heartRateImportingProvider(sessionId).notifier).state = true;
    try {
      final result = await action();
      ref.invalidate(trainingReportProvider(sessionId));
      ref.invalidate(heartRateAnalysisProvider(sessionId));
      ref.invalidate(trainingReplayProvider(sessionId));
      ref.invalidate(trainingSessionsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已保存 ${result.sampleCount} 条心率采样 · '
            '平均 ${result.average} · 最高 ${result.maximum} bpm',
          ),
        ),
      );
    } on IntervalsApiException catch (error) {
      if (context.mounted) _showError(context, error.message);
    } catch (error) {
      if (context.mounted) _showError(context, _friendlyError(error));
    } finally {
      if (context.mounted) {
        ref.read(heartRateImportingProvider(sessionId).notifier).state = false;
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导入失败：$message')),
    );
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('FormatException: ', '');

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条训练？'),
        content: const Text('训练和所有项目数据都会从本机永久删除，此操作无法撤销。'),
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
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final repository =
          await ref.read(trainingRepositoryFutureProvider.future);
      await repository.deleteSession(sessionId);
      ref.invalidate(trainingSessionsProvider);
      ref.invalidate(trainingReportProvider(sessionId));
      if (context.mounted) context.go('/history');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除训练失败：$error')),
      );
    }
  }
}

enum _HeartRateImportChoice { fit, intervalsIcu }

String _heartRateSourceLabel(String? source) => switch (source) {
      HeartRateSources.fit => '本地 FIT',
      HeartRateSources.intervalsIcu => 'Intervals.icu',
      _ => '未知来源',
    };

String _formatActivityStart(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _formatActivityDuration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.report,
    required this.heartRate,
    required this.importing,
    required this.exporting,
    required this.onImportHeartRate,
    required this.onReplay,
    required this.onExportReplay,
    required this.onRunningBreakdown,
    required this.onStationBreakdown,
    required this.onUndoFinalCompletion,
    required this.onEditActual,
  });

  final TrainingReport report;
  final AsyncValue<HeartRateAnalysis> heartRate;
  final bool importing;
  final bool exporting;
  final VoidCallback onImportHeartRate;
  final VoidCallback onReplay;
  final VoidCallback onExportReplay;
  final VoidCallback onRunningBreakdown;
  final VoidCallback onStationBreakdown;
  final VoidCallback? onUndoFinalCompletion;
  final ValueChanged<StationRecord> onEditActual;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (report.session.status == TrainingStatus.cancelled) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(child: Text('这场训练已取消，以下为取消前保存的数据。')),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (onUndoFinalCompletion != null) ...[
            OutlinedButton.icon(
              onPressed: onUndoFinalCompletion,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('误触完成？返回最后一项继续计时'),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    report.session.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatSessionDate(report.session.startedAt),
                    style: const TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    formatDuration(report.totalDuration),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Text('总时间', style: TextStyle(color: Colors.white60)),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      _Metric(
                        label: '跑步时间',
                        value: formatDuration(report.runningDuration),
                        onTap: onRunningBreakdown,
                      ),
                      _Metric(
                        label: '站点时间',
                        value: formatDuration(report.stationDuration),
                        onTap: onStationBreakdown,
                      ),
                      _Metric(
                        label: '转换时间',
                        value: formatDuration(report.transitionDuration),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeartRateCard(
                label: '平均心率',
                value: report.session.avgHeartRate,
              ),
              const SizedBox(width: 10),
              _HeartRateCard(
                label: '最高心率',
                value: report.session.maxHeartRate,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if ((report.session.heartRateSampleCount ?? 0) > 0)
            Text(
              '已保存 ${report.session.heartRateSampleCount} 条完整采样 · '
              '${_heartRateSourceLabel(report.session.heartRateSource)}',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: importing ? null : onImportHeartRate,
            icon: const Icon(Icons.monitor_heart_outlined),
            label: Text(
              report.session.avgHeartRate == null ? '导入心率' : '重新导入心率',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (report.session.heartRateSampleCount ?? 0) > 0
                ? onReplay
                : null,
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: Text(
              (report.session.heartRateSampleCount ?? 0) > 0
                  ? '训练回放'
                  : '导入心率后可回放',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: exporting ? null : onExportReplay,
            icon: exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(exporting ? '正在生成长图…' : '导出完整回放'),
          ),
          const SizedBox(height: 24),
          Text('项目明细', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ...report.stations.map(
            (station) => _StationRow(
              station: station,
              partnerName: report.session.partnerName,
              heartRate: heartRate.valueOrNull?.byStationId[station.id],
              onEditActual: station.status == SegmentStatus.completed
                  ? () => onEditActual(station)
                  : null,
            ),
          ),
          if (report.session.note?.isNotEmpty ?? false) ...[
            const SizedBox(height: 24),
            Text('备注', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(report.session.note!),
              ),
            ),
          ],
        ],
      );
}

String _friendlyExportError(Object error) {
  final message = error.toString();
  if (message.toLowerCase().contains('access') ||
      message.toLowerCase().contains('permission')) {
    return '没有相册权限，请在系统设置中允许保存照片';
  }
  return message
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          button: onTap != null,
          label: onTap == null ? null : '$label，查看每段明细',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: onTap == null
                                  ? Colors.white54
                                  : Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(label, style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 8),
                Text(
                  value == null ? '未导入' : '$value bpm',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      );
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.partnerName,
    required this.heartRate,
    required this.onEditActual,
  });

  final StationRecord station;
  final String? partnerName;
  final HeartRateSummary? heartRate;
  final VoidCallback? onEditActual;

  @override
  Widget build(BuildContext context) {
    final skipped = station.status == SegmentStatus.skipped;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${station.sequenceIndex + 1}',
                style: TextStyle(
                  color: station.type == StationType.run
                      ? Colors.greenAccent
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(station.displayName),
                  if (station.actualSpecification != null)
                    Text(
                      station.actualSpecification!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: station.actualMatchesTarget
                                ? Colors.greenAccent.shade100
                                : Colors.orangeAccent.shade100,
                          ),
                    ),
                  if (station.athleteName != null || station.athlete != null)
                    Text(
                      station.athleteName ??
                          athleteLabel(
                            station.athlete,
                            partnerName: partnerName,
                          ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                    ),
                  if (heartRate != null)
                    Text(
                      '平均 ${heartRate!.average} · 最高 ${heartRate!.maximum} bpm',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.redAccent.shade100,
                          ),
                    ),
                  if (station.transitionDuration != null)
                    Text(
                      '转换 ${formatDuration(station.transitionDuration, includeHours: false)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  skipped
                      ? '已跳过'
                      : formatDuration(station.duration, includeHours: false),
                  style: TextStyle(
                    color: skipped ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (onEditActual != null)
                  IconButton(
                    tooltip: '修改实际数据',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEditActual,
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
