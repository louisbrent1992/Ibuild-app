/// A release on one Google Play track, as the Play Developer API reports it.
class PlayRelease {
  const PlayRelease({
    required this.track,
    required this.status,
    this.name,
    this.versionCodes = const [],
    this.userFraction,
  });

  /// Reads one entry of `tracks[].releases[]`.
  factory PlayRelease.fromJson(String track, Map<String, dynamic> json) => PlayRelease(
        track: track,
        status: PlayReleaseStatus.parse(json['status']),
        name: json['name']?.toString(),
        versionCodes: [
          for (final v in (json['versionCodes'] as List? ?? const [])) int.tryParse('$v') ?? 0,
        ]..removeWhere((v) => v == 0),
        userFraction: (json['userFraction'] as num?)?.toDouble(),
      );

  final String track;
  final PlayReleaseStatus status;

  /// The release name, which Play defaults to `versionCode (versionName)`.
  final String? name;
  final List<int> versionCodes;

  /// Staged rollout fraction (0 to 1) while a rollout is in progress.
  final double? userFraction;

  int get highestVersionCode =>
      versionCodes.isEmpty ? 0 : versionCodes.reduce((a, b) => a > b ? a : b);

  String get label => name?.isNotEmpty == true
      ? name!
      : versionCodes.isEmpty
          ? 'Release'
          : 'Version code ${versionCodes.join(', ')}';

  String get statusLabel => switch (status) {
        PlayReleaseStatus.draft => 'Draft',
        PlayReleaseStatus.inProgress => userFraction == null
            ? 'Rolling out'
            : 'Rolling out to ${(userFraction! * 100).round()}%',
        PlayReleaseStatus.halted => 'Rollout halted',
        PlayReleaseStatus.completed => 'Available',
        PlayReleaseStatus.unknown => 'Unknown',
      };
}

enum PlayReleaseStatus {
  draft,
  inProgress,
  halted,
  completed,
  unknown;

  static PlayReleaseStatus parse(Object? raw) => switch ('$raw') {
        'draft' => draft,
        'inProgress' => inProgress,
        'halted' => halted,
        'completed' => completed,
        _ => unknown,
      };
}

/// Play's API names, as Play Console shows them.
String playTrackLabel(String track) => switch (track) {
      'internal' => 'Internal testing',
      'alpha' => 'Closed testing',
      'beta' => 'Open testing',
      'production' => 'Production',
      _ => track,
    };

/// Tracks in the order Play Console lists them; custom closed tracks follow.
int playTrackOrder(String track) {
  final i = const ['production', 'beta', 'alpha', 'internal'].indexOf(track);
  return i < 0 ? 4 : i;
}

/// Every release in a `GET edits/{id}/tracks` response, newest track first.
List<PlayRelease> parsePlayTracks(Object? json) {
  if (json is! Map) return const [];
  final releases = <PlayRelease>[];
  for (final track in (json['tracks'] as List? ?? const [])) {
    if (track is! Map) continue;
    final name = track['track']?.toString() ?? '';
    for (final release in (track['releases'] as List? ?? const [])) {
      if (release is Map) {
        releases.add(PlayRelease.fromJson(name, Map<String, dynamic>.from(release)));
      }
    }
  }
  releases.sort((a, b) {
    final byTrack = playTrackOrder(a.track).compareTo(playTrackOrder(b.track));
    return byTrack != 0 ? byTrack : b.highestVersionCode.compareTo(a.highestVersionCode);
  });
  return releases;
}

/// What iBuild reads from Play for one app.
class PlaySnapshot {
  const PlaySnapshot({this.releases = const [], this.testerGroups = const {}});

  final List<PlayRelease> releases;

  /// Google Groups per testing track. Play's API exposes only groups;
  /// email lists are managed in Play Console.
  final Map<String, List<String>> testerGroups;

  /// The release that carries [versionCode], if Play has one.
  PlayRelease? releaseFor(int versionCode) =>
      releases.where((r) => r.versionCodes.contains(versionCode)).firstOrNull;
}
