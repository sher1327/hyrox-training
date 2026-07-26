import 'package:go_router/go_router.dart';

import '../features/training/presentation/pages/create_training_page.dart';
import '../features/training/presentation/pages/dashboard_page.dart';
import '../features/training/presentation/pages/history_page.dart';
import '../features/training/presentation/pages/training_detail_page.dart';
import '../features/training/presentation/pages/training_segment_breakdown_page.dart';
import '../features/training/presentation/pages/training_timer_page.dart';
import '../features/training/presentation/pages/training_templates_page.dart';
import '../features/training/presentation/pages/template_editor_page.dart';
import '../features/replay/presentation/pages/training_replay_page.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
    GoRoute(
      path: '/training/new',
      builder: (_, __) => const CreateTrainingPage(),
    ),
    GoRoute(
      path: '/training/:id/live',
      builder: (_, state) => TrainingTimerPage(
        sessionId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/training/:id/replay',
      builder: (_, state) => TrainingReplayPage(
        sessionId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/training/:id/breakdown/:kind',
      builder: (_, state) => TrainingSegmentBreakdownPage(
        sessionId: int.parse(state.pathParameters['id']!),
        kind: state.pathParameters['kind'] ==
                TrainingBreakdownKind.station.routeName
            ? TrainingBreakdownKind.station
            : TrainingBreakdownKind.running,
      ),
    ),
    GoRoute(
      path: '/training/:id',
      builder: (_, state) => TrainingDetailPage(
        sessionId: int.parse(state.pathParameters['id']!),
        returnHomeOnBack:
            state.uri.queryParameters['source'] == 'training_completed',
      ),
    ),
    GoRoute(path: '/history', builder: (_, __) => const HistoryPage()),
    GoRoute(
      path: '/templates',
      builder: (_, __) => const TrainingTemplatesPage(),
    ),
    GoRoute(
      path: '/templates/new',
      builder: (_, __) => const TemplateEditorPage(),
    ),
    GoRoute(
      path: '/templates/:id/edit',
      builder: (_, state) => TemplateEditorPage(
        templateId: int.parse(state.pathParameters['id']!),
      ),
    ),
  ],
);
