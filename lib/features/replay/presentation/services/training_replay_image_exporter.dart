import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:screenshot/screenshot.dart';

import '../../domain/models/training_replay.dart';
import '../widgets/training_replay_export_view.dart';

final trainingReplayImageExporterProvider = Provider(
  (ref) => const TrainingReplayImageExporter(),
);

final trainingReplayExportingProvider =
    StateProvider.autoDispose.family<bool, int>((ref, sessionId) => false);

final class TrainingReplayExportResult {
  const TrainingReplayExportResult({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

final class TrainingReplayImageExporter {
  const TrainingReplayImageExporter();

  static const albumName = 'HYROX Training';

  Future<Uint8List> capture(
    BuildContext context,
    TrainingReplay replay, {
    double? pixelRatio,
  }) {
    return ScreenshotController().captureFromLongWidget(
      MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: const Size(TrainingReplayExportView.exportWidth, 1000),
        ),
        child: TrainingReplayExportView(replay: replay),
      ),
      context: context,
      delay: const Duration(milliseconds: 250),
      pixelRatio: pixelRatio ?? _pixelRatioFor(replay),
      constraints: const BoxConstraints.tightFor(
        width: TrainingReplayExportView.exportWidth,
      ),
    );
  }

  double _pixelRatioFor(TrainingReplay replay) {
    if (replay.segments.length > 60) return 1;
    if (replay.segments.length > 28) return 1.5;
    return 2;
  }

  Future<TrainingReplayExportResult> exportToGallery(
    BuildContext context,
    TrainingReplay replay,
  ) async {
    final bytes = await capture(context, replay);
    final fileName = _fileName(replay);
    await Gal.putImageBytes(bytes, album: albumName, name: fileName);
    return TrainingReplayExportResult(fileName: fileName, bytes: bytes);
  }

  String _fileName(TrainingReplay replay) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = replay.startedAt.toLocal();
    return 'HYROX_Replay_${local.year}${two(local.month)}${two(local.day)}_'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}';
  }
}
