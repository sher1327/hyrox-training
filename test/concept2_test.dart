import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyrox_training_tracker/features/concept2/data/services/concept2_logbook_client.dart';
import 'package:hyrox_training_tracker/features/concept2/domain/models/concept2_models.dart';

void main() {
  test('Concept2 detail parses PM5 intervals in tenths of a second', () {
    final result = Concept2Result.fromJson({
      'id': 42,
      'type': 'rower',
      'date_utc': '2026-08-13 04:00:00',
      'distance': 2000,
      'time': 4800,
      'rest_time': 1200,
      'workout_type': 'FixedDistanceInterval',
      'stroke_rate': 30,
      'drag_factor': 115,
      'workout': {
        'intervals': [
          {
            'type': 'distance',
            'distance': 1000,
            'time': 2380,
            'rest_time': 600,
            'stroke_rate': 29,
          },
          {
            'type': 'distance',
            'distance': 1000,
            'time': 2420,
            'rest_time': 600,
            'stroke_rate': 31,
          },
        ],
      },
    });

    expect(result.machine, Concept2Machine.rower);
    expect(result.workDuration, const Duration(minutes: 8));
    expect(result.restDuration, const Duration(minutes: 2));
    expect(result.intervals, hasLength(2));
    expect(result.intervals.last.strokeRate, 31);
    expect(result.intervals.last.workDuration, const Duration(minutes: 4, seconds: 2));
  });

  test('matcher prefers end time and total duration closest to app session', () {
    final sessionEnd = DateTime.utc(2026, 8, 13, 4);
    final sessionStart = sessionEnd.subtract(const Duration(minutes: 10));
    Concept2Result result(int id, int endOffsetMinutes, int totalTenths) =>
        Concept2Result(
          id: id,
          machine: Concept2Machine.rower,
          endedAt: sessionEnd.add(Duration(minutes: endOffsetMinutes)),
          distanceMeters: 2000,
          workTimeTenths: totalTenths,
          workoutType: 'JustRow',
          intervals: const [],
        );

    final matches = Concept2ResultMatcher.forSession(
      results: [result(1, 25, 6000), result(2, 1, 5900)],
      machine: Concept2Machine.rower,
      sessionStart: sessionStart,
      sessionEnd: sessionEnd,
    );

    expect(matches.first.id, 2);
  });

  test('client sends bearer token and parses result list', () async {
    final client = Concept2LogbookClient(
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer personal-token');
        expect(request.url.queryParameters['type'], 'skierg');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 8,
                'type': 'skierg',
                'date_utc': '2026-08-13 04:00:00',
                'distance': 1000,
                'time': 2400,
                'workout_type': 'JustRow',
              },
            ],
          }),
          200,
        );
      }),
    );

    final results = await client.listResults(
      credentials: const Concept2Credentials('personal-token'),
      machine: Concept2Machine.skierg,
      from: DateTime.utc(2026, 8, 12),
      to: DateTime.utc(2026, 8, 14),
    );

    expect(results.single.id, 8);
    expect(results.single.machine, Concept2Machine.skierg);
  });
}
