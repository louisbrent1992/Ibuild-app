import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/build.dart';
import 'api_client.dart';
import 'ci_provider.dart';

/// Codemagic REST API client. Docs: https://docs.codemagic.io/rest-api/
class CodemagicService implements CiProvider {
  CodemagicService(this._token, {http.Client? client})
      : _client = client ?? http.Client();

  final String _token;
  final http.Client _client;

  /// Set once the older `api.codemagic.io/builds/:id` endpoint stops
  /// answering, after which only the v3 endpoint is used.
  bool _legacyBuildEndpointGone = false;

  static const _host = 'api.codemagic.io';
  static const _v3Host = 'codemagic.io';

  @override
  String get name => 'Codemagic';

  Map<String, String> get _headers => {'x-auth-token': _token};

  Future<dynamic> _call(String method, Uri uri, {Object? body}) => sendJson(
        _client,
        service: name,
        method: method,
        uri: uri,
        headers: _headers,
        body: body,
      );

  @override
  Future<List<CiApp>> listApps() async {
    final json = await _call('GET', Uri.https(_host, '/apps'));
    final apps = json is Map ? json['applications'] : null;
    if (apps is! List) return const [];
    return apps
        .whereType<Map>()
        .map((raw) {
          final workflows = <String, String>{};
          final wf = raw['workflows'];
          if (wf is Map) {
            wf.forEach((key, value) {
              workflows[key.toString()] = value is Map && value['name'] != null
                  ? value['name'].toString()
                  : key.toString();
            });
          }
          final branches = raw['branches'];
          return CiApp(
            id: raw['_id']?.toString() ?? '',
            name: raw['appName']?.toString() ?? 'Untitled app',
            branches: branches is List
                ? branches.map((b) => b.toString()).toList()
                : const [],
            workflows: workflows,
          );
        })
        .where((app) => app.id.isNotEmpty)
        .toList();
  }

  @override
  Future<String> startBuild({
    required String appId,
    required String workflowId,
    required String branch,
  }) async {
    final json = await _call('POST', Uri.https(_host, '/builds'), body: {
      'appId': appId,
      'workflowId': workflowId,
      'branch': branch,
      'labels': ['ibuild'],
    });
    final id = json is Map ? json['buildId']?.toString() : null;
    if (id == null || id.isEmpty) {
      throw ApiException(
          name, 'Codemagic accepted the request but did not return a build ID.');
    }
    return id;
  }

  @override
  Future<Build> getBuild(String buildId) async {
    if (!_legacyBuildEndpointGone) {
      try {
        final json = await _call('GET', Uri.https(_host, '/builds/$buildId'));
        if (json is Map) {
          return Build.fromCodemagic(Map<String, dynamic>.from(json));
        }
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) rethrow;
        _legacyBuildEndpointGone = e.statusCode == 404 || e.statusCode == 410;
      }
    }
    final json =
        await _call('GET', Uri.https(_v3Host, '/api/v3/builds/$buildId'));
    if (json is! Map) {
      throw ApiException(
          name, 'Codemagic sent an unexpected response for build $buildId.');
    }
    return Build.fromCodemagic(Map<String, dynamic>.from(json));
  }

  @override
  Future<List<Build>> listBuilds({required String appId}) async {
    final query = {'appId': appId};
    dynamic json;
    try {
      json = await _call('GET', Uri.https(_host, '/builds', query));
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) rethrow;
      json = await _call('GET', Uri.https(_v3Host, '/api/v3/builds', query));
    }
    final list = json is List
        ? json
        : json is Map
            ? (json['builds'] ?? json['data'])
            : null;
    if (list is! List) return const [];
    final builds = list
        .whereType<Map>()
        .map((m) => Build.fromCodemagic(Map<String, dynamic>.from(m)))
        .where((b) => b.id.isNotEmpty && (b.appId.isEmpty || b.appId == appId))
        .toList();
    DateTime when(Build b) => b.createdAt ?? b.startedAt ?? DateTime(2000);
    builds.sort((a, b) => when(b).compareTo(when(a)));
    return builds;
  }

  @override
  Future<void> cancelBuild(String buildId) async {
    await _call('POST', Uri.https(_host, '/builds/$buildId/cancel'));
  }

  @override
  Future<String?> fetchStepLog(Build build, BuildStep step) async {
    final raw = step.logUrl;
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.parse(raw);
    final uri = parsed.hasScheme ? parsed : Uri.https(_host).resolveUri(parsed);
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } on Exception {
      throw ApiException(name, 'Could not load the log for "${step.name}".');
    }
  }

  /// Artifact URLs need the API token, which a browser does not have, so
  /// this asks Codemagic for a public link that expires in an hour.
  @override
  Future<Uri?> downloadUrl(Artefact artefact) async {
    final url = Uri.tryParse(artefact.url);
    if (url == null) return null;
    if (!url.path.startsWith('/artifacts/')) return url;
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    final json = await _call(
      'POST',
      Uri.parse('${artefact.url}/public-url'),
      body: {'expiresAt': expiresAt},
    );
    final public = json is Map ? json['url']?.toString() : null;
    return public == null ? null : Uri.tryParse(public);
  }

  @override
  Uri? webUrl(Build build) => build.appId.isEmpty
      ? null
      : Uri.https('codemagic.io', '/app/${build.appId}/build/${build.id}');
}
