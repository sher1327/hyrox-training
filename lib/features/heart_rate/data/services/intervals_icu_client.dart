import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/heart_rate_models.dart';
import '../../domain/models/intervals_models.dart';
import '../../domain/services/heart_rate_time_series_mapper.dart';

final class IntervalsApiException implements Exception {
  const IntervalsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get credentialsRejected => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

final class IntervalsIcuClient {
  IntervalsIcuClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<IntervalsActivity>> listActivities({
    required IntervalsCredentials credentials,
    required DateTime oldest,
    required DateTime newest,
  }) async {
    final uri = Uri.https(
      'intervals.icu',
      '/api/v1/athlete/${Uri.encodeComponent(credentials.athleteId)}/activities',
      {'oldest': _date(oldest), 'newest': _date(newest)},
    );
    final response = await _get(uri, credentials);
    final body = jsonDecode(response.body);
    if (body is! List) throw const FormatException('活动列表格式不正确');
    return body
        .whereType<Map<String, Object?>>()
        .map(IntervalsActivity.fromJson)
        .toList();
  }

  Future<List<HeartRateSample>> getHeartRateStream({
    required IntervalsCredentials credentials,
    required IntervalsActivity activity,
  }) async {
    final uri = Uri.https(
      'intervals.icu',
      '/api/v1/activity/${Uri.encodeComponent(activity.id)}/streams.json',
    );
    final response = await _get(uri, credentials);
    final body = jsonDecode(response.body);
    if (body is! List) throw const FormatException('心率流格式不正确');

    List<Object?>? times;
    List<Object?>? heartRates;
    for (final value in body.whereType<Map<String, Object?>>()) {
      final data = value['data'];
      if (data is! List) continue;
      if (value['type'] == 'time') times = data.cast<Object?>();
      if (value['type'] == 'heartrate') heartRates = data.cast<Object?>();
    }
    if (times == null || heartRates == null) {
      throw const FormatException('该活动没有可用的时间或心率流');
    }
    return HeartRateTimeSeriesMapper.fromRelativeStreams(
      startedAt: activity.startedAt,
      times: times,
      heartRates: heartRates,
      source: HeartRateSources.intervalsIcu,
    );
  }

  Future<http.Response> _get(
    Uri uri,
    IntervalsCredentials credentials,
  ) async {
    final authorization = base64Encode(
      utf8.encode('API_KEY:${credentials.apiKey}'),
    );
    late final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'Authorization': 'Basic $authorization',
          'Accept': 'application/json',
          'User-Agent': 'HYROX-Training-Tracker/0.3',
        },
      ).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const IntervalsApiException('无法连接 Intervals.icu，请检查网络后重试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        401 || 403 => '运动员 ID 或 API 密钥无效',
        429 => 'Intervals.icu 请求过于频繁，请稍后重试',
        _ => 'Intervals.icu 请求失败（${response.statusCode}）',
      };
      throw IntervalsApiException(message, statusCode: response.statusCode);
    }
    return response;
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
