import 'pipeline.dart';

class TestFlightBuild {
  const TestFlightBuild({
    required this.id,
    required this.buildNumber,
    required this.processingState,
    this.version,
    this.uploadedAt,
    this.expired = false,
  });

  final String id;
  final String buildNumber;

  /// Marketing version such as 2.4.1, when Apple returns it.
  final String? version;
  final String processingState;
  final DateTime? uploadedAt;
  final bool expired;

  TestFlightState get state => switch (processingState.toUpperCase()) {
        'VALID' => TestFlightState.ready,
        'PROCESSING' => TestFlightState.processing,
        'FAILED' || 'INVALID' => TestFlightState.failed,
        _ => TestFlightState.unknown,
      };

  String get label =>
      version == null ? 'Build $buildNumber' : '$version ($buildNumber)';

  String get stateLabel {
    if (expired) return 'Expired';
    return switch (state) {
      TestFlightState.ready => 'Ready to test',
      TestFlightState.processing => 'Processing at Apple',
      TestFlightState.failed => 'Failed processing',
      _ => processingState.toLowerCase(),
    };
  }
}

class BetaGroup {
  const BetaGroup({
    required this.id,
    required this.name,
    required this.isInternal,
    required this.publicLinkEnabled,
    this.publicLink,
  });

  final String id;
  final String name;
  final bool isInternal;
  final bool publicLinkEnabled;
  final String? publicLink;

  BetaGroup copyWith({bool? publicLinkEnabled, String? publicLink}) =>
      BetaGroup(
        id: id,
        name: name,
        isInternal: isInternal,
        publicLinkEnabled: publicLinkEnabled ?? this.publicLinkEnabled,
        publicLink: publicLink ?? this.publicLink,
      );
}
