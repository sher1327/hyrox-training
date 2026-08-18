import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../concept2/presentation/controllers/concept2_providers.dart';
import '../../../heart_rate/presentation/controllers/heart_rate_providers.dart';
import '../../../replay/presentation/controllers/training_replay_providers.dart';
import '../../../training/presentation/controllers/training_providers.dart';
import '../../../training/presentation/controllers/training_timer_controller.dart';
import '../../domain/models/database_backup.dart';
import '../controllers/database_backup_providers.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  bool _exporting = false;
  bool _restoring = false;

  bool get _busy => _exporting || _restoring;

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(currentDatabaseSummaryProvider);
    final lastBackup = ref.watch(lastExternalBackupProvider);
    final internalBackups = ref.watch(internalBackupSummariesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '本机数据',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  summary.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, _) => Text('读取失败：$error'),
                    data: (value) => _DatabaseStats(summary: value),
                  ),
                  const Divider(height: 30),
                  Text(
                    lastBackup.when(
                      loading: () => '上次外部备份：读取中…',
                      error: (_, __) => '上次外部备份：未知',
                      data: (value) => value == null
                          ? '尚未在本设备记录外部备份'
                          : '上次外部备份：${_formatDateTime(value)}',
                    ),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _exportBackup,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_exporting ? '正在生成备份…' : '导出完整备份'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _chooseRestoreFile,
            icon: _restoring
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.settings_backup_restore_rounded),
            label: Text(_restoring ? '正在恢复数据…' : '从备份恢复'),
          ),
          const SizedBox(height: 22),
          Text('本机安全快照', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          internalBackups.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, _) => Card(
              child: ListTile(title: Text('安全快照读取失败：$error')),
            ),
            data: (items) => items.isEmpty
                ? const Card(
                    child: ListTile(
                      leading: Icon(Icons.history_rounded),
                      title: Text('暂无自动快照'),
                      subtitle: Text('删除训练或恢复备份前会自动保留，最多保存 5 份。'),
                    ),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.history_rounded),
                            title: Text(_formatDateTime(item.modifiedAt)),
                            subtitle: Text(
                              '${item.trainingCount} 场训练 · '
                              '${item.heartRateSampleCount} 条心率 · '
                              '${item.readableSize}',
                            ),
                            trailing: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _restoreFromPath(item.path),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 22),
          const _InformationCard(
            icon: Icons.favorite_outline_rounded,
            title: '包含完整训练与器械数据',
            text: '备份包含全程心率、Intervals.icu 匹配信息、训练感受，'
                '以及 Concept2 总成绩、间歇和逐桨数据。',
          ),
          const SizedBox(height: 10),
          const _InformationCard(
            icon: Icons.key_off_outlined,
            title: '授权密钥不会导出',
            text: 'Intervals.icu API 密钥和 Concept2 Token 保存在 Android '
                '安全存储中，换手机恢复后需要重新配置。',
          ),
          const SizedBox(height: 10),
          const _InformationCard(
            icon: Icons.warning_amber_rounded,
            title: '请保存到 App 外部',
            text: '建议将 .hyroxbackup 文件保存到 Downloads、电脑或网盘。'
                '卸载 App 或清除应用数据会同时删除 App 内部的自动快照。',
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _exporting = true);
    final service = ref.read(databaseBackupServiceProvider);
    BackupSnapshot? snapshot;
    try {
      snapshot = await service.createExportSnapshot();
      final now = DateTime.now();
      final saved = await ref.read(backupDocumentWriterProvider).save(
            sourcePath: snapshot.path,
            suggestedName: service.suggestedFileName(now),
          );
      if (!saved) return;
      await service.markExternalBackupCreated(now);
      ref.invalidate(lastExternalBackupProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('备份已保存'),
          content: Text(
            '训练 ${snapshot!.summary.trainingCount} 场\n'
            '心率采样 ${snapshot.summary.heartRateSampleCount} 条\n'
            '文件大小 ${snapshot.summary.readableSize}\n\n'
            '请保留这个 .hyroxbackup 文件。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } on DatabaseBackupException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('导出备份失败：$error');
    } finally {
      if (snapshot != null) await service.deleteTemporarySnapshot(snapshot);
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _chooseRestoreFile() async {
    const backupType = XTypeGroup(
      label: 'HYROX backup',
      extensions: ['hyroxbackup', 'db', 'sqlite'],
      mimeTypes: ['application/octet-stream', 'application/vnd.sqlite3'],
    );
    final file = await openFile(acceptedTypeGroups: const [backupType]);
    if (file == null || !mounted) return;
    await _restoreFromPath(file.path);
  }

  Future<void> _restoreFromPath(String path) async {
    setState(() => _restoring = true);
    try {
      final service = ref.read(databaseBackupServiceProvider);
      final incoming = await service.inspect(path);
      final current = await service.currentSummary();
      if (!mounted) return;
      if (current.activeTrainingCount > 0) {
        _showError('当前有正在进行的训练，请先完成或取消后再恢复');
        return;
      }
      final confirmed = await _confirmRestore(incoming, current);
      if (confirmed != true || !mounted) return;
      final result = await service.restore(path);
      if (!mounted) return;
      _invalidateDatabaseProviders();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('数据恢复完成'),
          content: Text(
            '已恢复 ${result.restored.trainingCount} 场训练、'
            '${result.restored.heartRateSampleCount} 条心率采样。\n\n'
            '恢复前的本机数据已经自动保存为内部安全快照。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回首页'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/');
    } on DatabaseBackupException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<bool?> _confirmRestore(
    DatabaseBackupSummary incoming,
    DatabaseBackupSummary current,
  ) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('恢复整个备份？'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('备份内容', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('训练记录：${incoming.trainingCount} 场'),
              Text('自定义模板：${incoming.customTemplateCount} 个'),
              Text('项目分段：${incoming.stationRecordCount} 条'),
              Text('心率采样：${incoming.heartRateSampleCount} 条'),
              Text('数据库版本：v${incoming.databaseVersion}'),
              Text('文件大小：${incoming.readableSize}'),
              Text('校验码：${incoming.sha256.substring(0, 12)}…'),
              if (incoming.activeTrainingCount > 0) ...[
                const SizedBox(height: 10),
                const Text(
                  '该备份包含一场进行中的训练，恢复后可以继续计时。',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              ],
              const Divider(height: 28),
              Text(
                '当前本机的 ${current.trainingCount} 场训练将被备份内容替换。'
                '恢复前会自动创建安全快照，失败时会自动回滚。',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );

  void _invalidateDatabaseProviders() {
    ref.invalidate(trainingRepositoryFutureProvider);
    ref.invalidate(trainingTemplateRepositoryFutureProvider);
    ref.invalidate(trainingSessionsProvider);
    ref.invalidate(trainingTemplatesProvider);
    ref.invalidate(trainingReportProvider);
    ref.invalidate(trainingTimerProvider);
    ref.invalidate(heartRateRepositoryFutureProvider);
    ref.invalidate(heartRateImportServiceFutureProvider);
    ref.invalidate(heartRateAnalysisProvider);
    ref.invalidate(heartRateSourcesProvider);
    ref.invalidate(trainingReplayProvider);
    ref.invalidate(concept2RepositoryFutureProvider);
    ref.invalidate(concept2ResultProvider);
    ref.invalidate(currentDatabaseSummaryProvider);
    ref.invalidate(internalBackupSummariesProvider);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _DatabaseStats extends StatelessWidget {
  const _DatabaseStats({required this.summary});

  final DatabaseBackupSummary summary;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Stat(label: '训练记录', value: '${summary.trainingCount} 场'),
          _Stat(label: '自定义模板', value: '${summary.customTemplateCount} 个'),
          _Stat(label: '项目分段', value: '${summary.stationRecordCount} 条'),
          _Stat(label: '心率采样', value: '${summary.heartRateSampleCount} 条'),
          _Stat(label: '数据库', value: 'v${summary.databaseVersion}'),
          _Stat(label: '当前大小', value: summary.readableSize),
        ],
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: (MediaQuery.sizeOf(context).width - 68) / 2,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(text),
        ),
      );
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
