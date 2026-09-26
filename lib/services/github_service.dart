import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/repo.dart';
import 'api_client.dart';
import 'yaml_parsing.dart';

/// Where the source lives. GitHub first; GitLab or Bitbucket can follow.
abstract class SourceHost {
  Future<String> currentUser();
  Future<List<GitHubRepo>> listRepos();
  Future<List<String>> listBranches(String repo);
  Future<String?> readFile(String repo, String path, {String? ref});
  Future<void> writeFile(
    String repo,
    String path,
    String content, {
    required String message,
    String? branch,
  });
  Future<ProjectDetection> detect(String repo, {String? ref});
}

class GitHubService implements SourceHost {
  GitHubService(this._token, {http.Client? client})
      : _client = client ?? http.Client();

  final String _token;
  final http.Client _client;

  static const _host = 'api.github.com';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<dynamic> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) =>
      sendJson(
        _client,
        service: 'GitHub',
        method: method,
        uri: Uri.https(_host, path, query),
        headers: _headers,
        body: body,
      );

  @override
  Future<String> currentUser() async {
    final json = await _call('GET', '/user');
    return json is Map ? (json['login']?.toString() ?? 'unknown') : 'unknown';
  }

  @override
  Future<List<GitHubRepo>> listRepos() async {
    final json = await _call('GET', '/user/repos',
        query: {'per_page': '100', 'sort': 'updated'});
    if (json is! List) return const [];
    return json
        .whereType<Map>()
        .map((r) => GitHubRepo(
              fullName: r['full_name']?.toString() ?? '',
              defaultBranch: r['default_branch']?.toString() ?? 'main',
              isPrivate: r['private'] == true,
              description: r['description']?.toString(),
            ))
        .where((r) => r.fullName.isNotEmpty)
        .toList();
  }

  @override
  Future<List<String>> listBranches(String repo) async {
    final json =
        await _call('GET', '/repos/$repo/branches', query: {'per_page': '100'});
    if (json is! List) return const [];
    return json
        .whereType<Map>()
        .map((b) => b['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> _contents(String repo, String path,
      {String? ref}) async {
    try {
      final json = await _call('GET', '/repos/$repo/contents/$path',
          query: ref == null ? null : {'ref': ref});
      return json is Map ? Map<String, dynamic>.from(json) : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<String?> readFile(String repo, String path, {String? ref}) async {
    final json = await _contents(repo, path, ref: ref);
    final content = json?['content'];
    if (content is! String) return null;
    final bytes = base64.decode(content.replaceAll(RegExp(r'\s'), ''));
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> writeFile(
    String repo,
    String path,
    String content, {
    required String message,
    String? branch,
  }) async {
    final existing = await _contents(repo, path, ref: branch);
    final sha = existing?['sha'];
    await _call('PUT', '/repos/$repo/contents/$path', body: {
      'message': message,
      'content': base64.encode(utf8.encode(content)),
      if (branch != null) 'branch': branch,
      if (sha != null) 'sha': sha,
    });
  }

  @override
  Future<ProjectDetection> detect(String repo, {String? ref}) async {
    final json = await _call('GET', '/repos/$repo/contents',
        query: ref == null ? null : {'ref': ref});
    final entries = json is List ? json.whereType<Map>().toList() : <Map>[];
    bool has(String name, String type) =>
        entries.any((e) => e['name'] == name && e['type'] == type);

    final hasPubspec = has('pubspec.yaml', 'file');
    final hasCodemagic = has('codemagic.yaml', 'file');
    final pubspec = hasPubspec
        ? parsePubspec(await readFile(repo, 'pubspec.yaml', ref: ref) ?? '')
        : const PubspecInfo();
    final codemagic = hasCodemagic
        ? parseCodemagicYaml(
            await readFile(repo, 'codemagic.yaml', ref: ref) ?? '')
        : const CodemagicInfo();

    return ProjectDetection(
      hasPubspec: hasPubspec,
      hasIos: has('ios', 'dir'),
      hasAndroid: has('android', 'dir'),
      hasCodemagicYaml: hasCodemagic,
      appName: pubspec.name,
      version: pubspec.version,
      workflows: codemagic.workflows,
      bundleId: codemagic.bundleId,
    );
  }
}
