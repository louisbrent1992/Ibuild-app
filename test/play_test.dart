import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/models/build.dart';
import 'package:ibuild/models/pipeline.dart';
import 'package:ibuild/models/play.dart';
import 'package:ibuild/models/project.dart';

void main() {
  // Shape of a real `edits/{id}/tracks` response.
  const tracks = {
    'tracks': [
      {'track': 'production'},
      {
        'track': 'alpha',
        'releases': [
          {
            'name': '2 (1.0.0)',
            'versionCodes': ['2'],
            'status': 'draft',
          },
        ],
      },
      {
        'track': 'production-2',
        'releases': [
          {
            'versionCodes': ['1'],
            'status': 'inProgress',
            'userFraction': 0.2,
          },
        ],
      },
    ],
  };

  test('parses releases, skipping tracks without any', () {
    final releases = parsePlayTracks(tracks);
    expect(releases.map((r) => r.track), ['alpha', 'production-2']);
    expect(releases.first.versionCodes, [2]);
    expect(releases.first.statusLabel, 'Draft');
    expect(releases.last.statusLabel, 'Rolling out to 20%');
    expect(playTrackLabel('alpha'), 'Closed testing');
  });

  test('finds the release carrying a version code', () {
    final snap = PlaySnapshot(releases: parsePlayTracks(tracks));
    expect(snap.releaseFor(2)?.track, 'alpha');
    expect(snap.releaseFor(3), isNull);
  });

  test('reads the version code Codemagic reports for a bundle', () {
    final a = Artefact.fromJson(
        {'name': 'app-release.aab', 'type': 'aab', 'versionCode': '2'});
    expect(a.versionCode, 2);
  });

  group('Android store station', () {
    final build = Build(id: 'b', appId: 'a', status: BuildStatus.finished);
    StationState store(TestFlightState s) =>
        computePipeline(build, testFlight: s, platform: AppPlatform.android)[
            Station.store];

    test('waits until Play shows the release', () {
      expect(store(TestFlightState.unknown), StationState.pending);
      expect(store(TestFlightState.ready), StationState.done);
    });
  });
}
