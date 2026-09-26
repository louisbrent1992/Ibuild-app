import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import '../models/testflight.dart';
import 'api_client.dart';

abstract class StoreConnect {
  Future<void> verify();
  Future<String?> findAppId(String bundleId);
  Future<List<TestFlightBuild>> recentBuilds(String appId);
  Future<List<BetaGroup>> betaGroups(String appId);
  Future<BetaGroup> enablePublicLink(BetaGroup group);
}

/// App Store Connect API client, authenticated with a team API key.
/// Docs: https://developer.apple.com/documentation/appstoreconnectapi
class AppStoreConnectService implements StoreConnect {
  AppStoreConnectService({
    required this.issuerId,
    required this.keyId,
    required this.privateKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String issuerId;
  final String keyId;
  final String privateKey;
  final http.Client _client;

  String? _token;
  DateTime? _expires;

  static const _host = 'api.appstoreconnect.apple.com';
  static const _service = 'App Store Connect';

  /// Apple accepts ES256 tokens that live for at most 20 minutes.
  String _bearer() {
    final now = DateTime.now();
    final cached = _token;
    final expires = _expires;
    if (cached != null &&
        expires != null &&
        now.isBefore(expires.subtract(const Duration(minutes: 2)))) {
      return cached;
    }
    final expiry = now.add(const Duration(minutes: 15));
    final jwt = JWT(
      {
        'iss': issuerId,
        'exp': expiry.millisecondsSinceEpoch ~/ 1000,
        'aud': 'appstoreconnect-v1',
      },
      header: {'kid': keyId, 'typ': 'JWT'},
    );
    final String token;
    try {
      token = jwt.sign(ECPrivateKey(privateKey.trim()),
          algorithm: JWTAlgorithm.ES256);
    } catch (_) {
      throw ApiException(_service,
          'The private key could not be read. Paste the whole .p8 file, including the BEGIN and END lines.');
    }
    _token = token;
    _expires = expiry;
    return token;
  }

  Future<dynamic> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async =>
      sendJson(
        _client,
        service: _service,
        method: method,
        uri: Uri.https(_host, path, query),
        headers: {'Authorization': 'Bearer ${_bearer()}'},
        body: body,
      );

  @override
  Future<void> verify() async {
    await _call('GET', '/v1/apps', query: {'limit': '1'});
  }

  @override
  Future<String?> findAppId(String bundleId) async {
    final json = await _call('GET', '/v1/apps',
        query: {'filter[bundleId]': bundleId, 'limit': '1'});
    final data = json is Map ? json['data'] : null;
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map)['id']?.toString();
    }
    return null;
  }

  @override
  Future<List<TestFlightBuild>> recentBuilds(String appId) async {
    final json = await _call('GET', '/v1/builds', query: {
      'filter[app]': appId,
      'sort': '-uploadedDate',
      'limit': '10',
      'include': 'preReleaseVersion',
    });
    if (json is! Map) return const [];

    final versions = <String, String>{};
    final included = json['included'];
    if (included is List) {
      for (final item in included.whereType<Map>()) {
        final attributes = item['attributes'];
        if (item['type'] == 'preReleaseVersions' &&
            attributes is Map &&
            attributes['version'] != null) {
          versions[item['id'].toString()] = attributes['version'].toString();
        }
      }
    }

    final data = json['data'];
    if (data is! List) return const [];
    return data.whereType<Map>().map((item) {
      final attributes = item['attributes'] is Map ? item['attributes'] as Map : const {};
      String? versionId;
      final relationships = item['relationships'];
      if (relationships is Map && relationships['preReleaseVersion'] is Map) {
        final linked = (relationships['preReleaseVersion'] as Map)['data'];
        if (linked is Map) versionId = linked['id']?.toString();
      }
      return TestFlightBuild(
        id: item['id'].toString(),
        buildNumber: attributes['version']?.toString() ?? '?',
        version: versionId == null ? null : versions[versionId],
        processingState:
            attributes['processingState']?.toString() ?? 'UNKNOWN',
        uploadedAt:
            DateTime.tryParse(attributes['uploadedDate']?.toString() ?? '')
                ?.toLocal(),
        expired: attributes['expired'] == true,
      );
    }).toList();
  }

  @override
  Future<List<BetaGroup>> betaGroups(String appId) async {
    final json = await _call('GET', '/v1/apps/$appId/betaGroups',
        query: {'limit': '50'});
    final data = json is Map ? json['data'] : null;
    if (data is! List) return const [];
    return data.whereType<Map>().map(_group).toList();
  }

  BetaGroup _group(Map item) {
    final attributes = item['attributes'] is Map ? item['attributes'] as Map : const {};
    return BetaGroup(
      id: item['id'].toString(),
      name: attributes['name']?.toString() ?? 'Unnamed group',
      isInternal: attributes['isInternalGroup'] == true,
      publicLinkEnabled: attributes['publicLinkEnabled'] == true,
      publicLink: attributes['publicLink']?.toString(),
    );
  }

  /// Turns on the group's public TestFlight link so it can be shared.
  @override
  Future<BetaGroup> enablePublicLink(BetaGroup group) async {
    final json = await _call('PATCH', '/v1/betaGroups/${group.id}', body: {
      'data': {
        'type': 'betaGroups',
        'id': group.id,
        'attributes': {'publicLinkEnabled': true},
      },
    });
    final data = json is Map ? json['data'] : null;
    return data is Map ? _group(data) : group.copyWith(publicLinkEnabled: true);
  }
}
