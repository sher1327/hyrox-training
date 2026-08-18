import 'package:flutter/material.dart';

import '../../domain/models/training_models.dart';

Future<TrainingReflection?> showTrainingReflectionEditor(
  BuildContext context,
  TrainingSession session,
) async {
  var effort = session.perceivedEffort ?? 5;
  var feeling = session.feeling ?? TrainingFeeling.neutral;
  final noteController = TextEditingController(text: session.note ?? '');
  final result = await showModalBottomSheet<TrainingReflection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '训练感受与备注',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              Text('主观强度（RPE） $effort / 10'),
              Slider(
                value: effort.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$effort',
                onChanged: (value) => setState(() => effort = value.round()),
              ),
              const SizedBox(height: 8),
              const Text('整体感受'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TrainingFeeling.values
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value.label),
                        selected: feeling == value,
                        onSelected: (_) => setState(() => feeling = value),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: noteController,
                minLines: 3,
                maxLines: 7,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: '训练备注',
                  hintText: '身体状态、器械感受、需要改进的项目……',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  TrainingReflection(
                    perceivedEffort: effort,
                    feeling: feeling,
                    note: noteController.text.trim(),
                  ),
                ),
                child: const Text('保存训练感受'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  noteController.dispose();
  return result;
}
