import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class RunningLapDistanceEdit {
  const RunningLapDistanceEdit(this.distanceMeters);

  final int? distanceMeters;
}

Future<RunningLapDistanceEdit?> showRunningLapDistanceEditor(
  BuildContext context, {
  int? initialDistanceMeters,
  required int lapNumber,
}) async {
  final controller = TextEditingController(
    text: initialDistanceMeters?.toString() ?? '',
  );
  String? error;
  final result = await showDialog<RunningLapDistanceEdit>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('第 $lapNumber 段距离'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('距离可以稍后补填；填写后会自动计算该段平均配速。'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '距离（米）',
                hintText: '例如 400',
                suffixText: 'm',
                errorText: error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [200, 400, 800, 1000]
                  .map(
                    (distance) => ActionChip(
                      label: Text('$distance m'),
                      onPressed: () {
                        controller.text = '$distance';
                        setState(() => error = null);
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后填写'),
          ),
          if (initialDistanceMeters != null)
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                const RunningLapDistanceEdit(null),
              ),
              child: const Text('清除距离'),
            ),
          FilledButton(
            onPressed: () {
              final distance = int.tryParse(controller.text.trim());
              if (distance == null || distance <= 0) {
                setState(() => error = '请输入大于 0 的距离');
                return;
              }
              Navigator.pop(context, RunningLapDistanceEdit(distance));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}
