// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyrox_training_tracker/app/app.dart';
import 'package:hyrox_training_tracker/features/training/presentation/controllers/training_providers.dart';

void main() {
  testWidgets('dashboard renders primary training action',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingSessionsProvider.overrideWith((ref) async => []),
        ],
        child: const HyroxApp(),
      ),
    );

    expect(find.text('HYROX'), findsOneWidget);
    expect(find.text('创建训练'), findsOneWidget);
  });
}
