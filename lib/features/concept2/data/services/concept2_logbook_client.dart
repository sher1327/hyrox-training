import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/concept2_models.dart';

final class Concept2ApiException implements Exception {
  const Concept2ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get credentialsRejected => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

final class Concept2LogbookClient {
  Concept2LogbookClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<Concept2Result>> listResults({
    required Concept2Credentials credentials,
    required Concept2Machine machine,
    required DateTime from,
    required DateTime to,
  }) async {
    final uri = Uri.https('log.concept2.com', '/api/users/me/results', {
      'from': _date(from),
      'to': _date(to),
      'type': machine.apiValue,
      'number': '250',
    });
    final response = await _get(uri, credentials);
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! List) {
      throw const FormatException('Concept2 训练列表格式不正确');
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((value) => Concept2Result.fromJson(value.cast<String, Object?>()))
        .toList();
  }

  Future<Concept2Result> getResult({
    required Concept2Credentials credentials,
    required int resultId,
  }) async {
    final uri = Uri.https(
      'log.concept2.com',
      '/api/users/me/results/$resultId',
    );
    final response = await _get(uri, credentials);
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! Map) {
      throw const FormatException('Concept2 训练详情格式不正确');
    }
    return Concept2Result.fromJson(
      (body['data'] as Map).cast<String, Object?>(),
    );
  }

  Future<List<Concept2Stroke>> getStrokes({
    required Concept2Credentials credentials,
    required int resultId,
  }) async {
    final uri = Uri.https(
      'log.concept2.com',
      '/api/users/me/results/$resultId/strokes',
    );
    late final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const Concept2ApiException('无法连接 Concept2 Logbook，请检查网络');
    }
    // Stroke data is optional in Logbook. A missing export must not prevent
    // the total result and interval data from being synchronized.
    if (response.statusCode == 404) return const [];
    _throwForFailure(response);
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! List) {
      throw const FormatException('Concept2 逐桨数据格式不正确');
    }
    return Concept2Stroke.listFromJson(
      (body['data'] as List).cast<Object?>(),
    );
  }

  Future<http.Response> _get(
    Uri uri,
    Concept2Credentials credentials,
  ) async {
    late final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const Concept2ApiException('无法连接 Concept2 Logbook，请检查网络');
    }
    _throwForFailure(response);
    return response;
  }

  Map<String, String> _headers(Concept2Credentials credentials) => {
        'Authorization': 'Bearer ${credentials.accessToken}',
        'Accept': 'application/vnd.c2logbook.v1+json',
        'User-Agent': 'HYROX-Training-Tracker/1.0',
      };

  void _throwForFailure(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final message = switch (response.statusCode) {
      401 || 403 => 'Concept2 授权 Token 无效或已失效',
      404 => 'Concept2 训练记录不存在',
      _ => 'Concept2 请求失败（${response.statusCode}）',
    };
    throw Concept2ApiException(message, statusCode: response.statusCode);
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
