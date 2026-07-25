import 'package:flutter/material.dart';

import '../../domain/models/training_models.dart';
import '../formatters/training_formatters.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({
    required this.session,
    required this.onTap,
    super.key,
  });

  final TrainingSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = session.status == TrainingStatus.inProgress;
    final cancelled = session.status == TrainingStatus.cancelled;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (active
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFF2B3032))
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  active ? Icons.timer_outlined : Icons.directions_run,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatSessionDate(session.startedAt)} · '
                      '${trainingModeLabel(session.mode)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    active
                        ? '进行中'
                        : cancelled
                            ? '已取消'
                            : formatDuration(session.totalDuration),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active
                        ? '继续训练'
                        : cancelled
                            ? formatDuration(session.totalDuration)
                            : '查看报告',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
