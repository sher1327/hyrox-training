import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ble_heart_rate_models.dart';
import '../controllers/live_heart_rate_controller.dart';

class LiveHeartRateCard extends ConsumerWidget {
  const LiveHeartRateCard({required this.sessionId, super.key});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(liveHeartRateControllerProvider(sessionId));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => showLiveHeartRateSheet(
          context: context,
          sessionId: sessionId,
        ),
        leading: Icon(
          Icons.favorite_rounded,
          color: value.isConnected ? Colors.redAccent : Colors.white38,
        ),
        title: Text(
          value.currentBpm == null ? '连接实时心率带' : '${value.currentBpm} bpm',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          value.connectedDevice?.displayName ?? _statusLabel(value.status),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value.savedSampleCount > 0)
              Text(
                '${value.savedSampleCount} 条',
                style: const TextStyle(color: Colors.white54),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

Future<void> showLiveHeartRateSheet({
  required BuildContext context,
  required int sessionId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .82,
        child: _LiveHeartRateSheet(sessionId: sessionId),
      ),
    );

class _LiveHeartRateSheet extends ConsumerWidget {
  const _LiveHeartRateSheet({required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(liveHeartRateControllerProvider(sessionId));
    final controller =
        ref.read(liveHeartRateControllerProvider(sessionId).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '实时心率带',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (value.connectedDevice != null)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded, color: Colors.redAccent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value.connectedDevice!.displayName),
                        Text(
                          value.isConnected
                              ? '已连接并保存采样'
                              : _statusLabel(value.status),
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    value.currentBpm == null ? '--' : '${value.currentBpm}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(' bpm'),
                ],
              ),
            ),
          ),
        if (value.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              value.message!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(
            onPressed: value.status == BleHeartRateConnectionStatus.scanning
                ? null
                : controller.startScan,
            icon: value.status == BleHeartRateConnectionStatus.scanning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching_rounded),
            label: Text(
              value.status == BleHeartRateConnectionStatus.scanning
                  ? '正在扫描标准心率设备…'
                  : '扫描心率带',
            ),
          ),
        ),
        Expanded(
          child: value.devices.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '心率带需要支持标准 Bluetooth Heart Rate Service。\n'
                      '佩戴并唤醒心率带后开始扫描。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: value.devices.length,
                  itemBuilder: (context, index) {
                    final device = value.devices[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.monitor_heart_outlined),
                        title: Text(device.displayName),
                        subtitle: Text('信号 ${device.rssi} dBm'),
                        trailing: const Text('连接'),
                        onTap: () => controller.connect(device),
                      ),
                    );
                  },
                ),
        ),
        if (value.connectedDevice != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: controller.stopRecording,
              child: const Text('断开并保存'),
            ),
          ),
      ],
    );
  }
}

String _statusLabel(BleHeartRateConnectionStatus status) => switch (status) {
      BleHeartRateConnectionStatus.idle => '尚未连接',
      BleHeartRateConnectionStatus.scanning => '正在扫描',
      BleHeartRateConnectionStatus.connecting => '正在连接',
      BleHeartRateConnectionStatus.connected => '已连接',
      BleHeartRateConnectionStatus.disconnected => '已断开',
      BleHeartRateConnectionStatus.unavailable => '蓝牙或权限不可用',
      BleHeartRateConnectionStatus.error => '连接发生错误',
    };
