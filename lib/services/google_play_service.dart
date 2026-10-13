import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import '../models/play.dart';
import 'api_client.dart';

abstract class PlayConsole {
  /// Releases on every track, plus tester groups on the testing tracks.
  Future<PlaySnapshot> snapshot(String packageName);
}

/// Google Play Developer API client, authenticated with a service account
/// JSON key. iBuild only reads: every edit it opens is deleted unchanged.
/// Docs: https://developers.google.com/android-publisher
class GooglePlayService implements PlayConsole {
  GooglePlayService(String serviceAccountJson, {http.Client? client})
      : _client = client ?? http.Client() {
    final Object? decoded;
    try {
      decoded = jsonDecode(serviceAccountJson);
    } on FormatException {
      throw ApiException(_service, _badKey);
    }
    if (decoded is! Map ||
        decoded['client_email'] is! String ||
        decoded['private_key'] is! String) {
      throw ApiException(_service, _badKey);
    }
    clientEmail = decoded['client_email'] as String;
    _privateKey = decoded['private_key'] as String;
  }

  late final String clientEmail;
  late final String _privateKey;
  final http.Client _client;

  String? _token;
  DateTime? _expires;

  static const _service = 'Google Play';
  static const _badKey =
      'That is not a service account key. Paste the whole JSON file you downloaded from Google Cloud.';
  static const _testingTracks = ['internal', 'alpha', 'beta'];

  /// Trades a signed assertion for an hour-long access token.
  Future<String> _bearer() async {
    final cached = _token;
    final expires = _expires;
    if (cached != null && expires != null && DateTime.now().isBefore(expires)) {
      return cached;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final String assertion;
    try {
      assertion = JWT({
        'iss': clientEmail,
        'scope': 'https://www.googleapis.com/auth/androidpublisher',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
      }).sign(RSAPrivateKey(_privateKey), algorithm: JWTAlgorithm.RS256);
    } catch (_) {
      throw ApiException(_service, _badKey);
    }
    final http.Response response;
    try {
      response = await _client.post(
        Uri.https('oauth2.googleapis.com', '/token'),
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': assertion,
        },
      ).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException(_service, 'Could not reach Google to sign in.');
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _service,
        describeFailure(_service, response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }
    final token = (jsonDecode(response.body) as Map)['access_token'] as String;
    _token = token;
    _expires = DateTime.now().add(const Duration(minutes: 50));
    return token;
  }

  /// Checks that Google accepts the key.
  Future<void> verify() => _bearer();

  Future<dynamic> _call(String method, String path) async => sendJson(
        _client,
        service: _service,
        method: method,
        uri: Uri.https(
            'androidpublisher.googleapis.com', '/androidpublisher/v3/applications/$path'),
        headers: {'Authorization': 'Bearer ${await _bearer()}'},
      );

  @override
  Future<PlaySnapshot> snapshot(String packageName) async {
    // Play only serves tracks inside an edit; this one is never committed.
    final edit = (await _call('POST', '$packageName/edits') as Map)['id'];
    final base = '$packageName/edits/$edit';
    try {
      final releases = parsePlayTracks(await _call('GET', '$base/tracks'));
      final groups = <String, List<String>>{};
      for (final track in _testingTracks) {
        final testers = await _call('GET', '$base/testers/$track');
        final list = testers is Map ? testers['googleGroups'] : null;
        if (list is List && list.isNotEmpty) {
          groups[track] = [for (final g in list) '$g'];
        }
      }
      return PlaySnapshot(releases: releases, testerGroups: groups);
    } finally {
      try {
        await _call('DELETE', base);
      } catch (_) {
        // Unused edits expire on their own.
      }
    }
  }
}
