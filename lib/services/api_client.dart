import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failed call to one of the services iBuild talks to. The message is
/// written for the person holding the phone, not for a log file.
class ApiException implements Exception {
  ApiException(this.service, this.message, {this.statusCode});

  final String service;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Sends a JSON request and returns the decoded body (or null if empty).
Future<dynamic> sendJson(
  http.Client client, {
  required String service,
  required String method,
  required Uri uri,
  Map<String, String> headers = const {},
  Object? body,
}) async {
  final request = http.Request(method, uri)
    ..headers.addAll({'Accept': 'application/json', ...headers});
  if (body != null) {
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);
  }

  final http.Response response;
  try {
    final streamed =
        await client.send(request).timeout(const Duration(seconds: 30));
    response = await http.Response.fromStream(streamed);
  } on TimeoutException {
    throw ApiException(service,
        '$service did not answer within 30 seconds. Check your connection and try again.');
  } on http.ClientException catch (e) {
    throw ApiException(service, 'Could not reach $service: ${e.message}');
  }

  if (response.statusCode >= 200 && response.statusCode < 300) {
    if (response.body.trim().isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return response.body;
    }
  }
  throw ApiException(
    service,
    describeFailure(service, response.statusCode, response.body),
    statusCode: response.statusCode,
  );
}

String describeFailure(String service, int status, String body) {
  String? detail;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        final first = errors.first as Map;
        detail = (first['detail'] ?? first['title'] ?? first['message'])
            ?.toString();
      }
      // Google APIs nest it: {"error": {"code": 403, "message": "..."}}.
      final error = decoded['error'];
      if (error is Map) detail ??= error['message']?.toString();
      detail ??= (decoded['message'] ?? decoded['error'])?.toString();
    }
  } on FormatException {
    // Not JSON. The status-based message below still applies.
  }
  final hint = switch (status) {
    401 => '$service rejected the token. Update it in Settings.',
    403 => 'The $service token does not have permission for this.',
    404 => '$service could not find that item.',
    422 => '$service could not accept the request.',
    429 => '$service is limiting requests. Wait a minute and try again.',
    >= 500 => '$service is having problems (HTTP $status). Try again shortly.',
    _ => '$service returned HTTP $status.',
  };
  return detail == null || detail.isEmpty ? hint : '$hint $detail';
}
