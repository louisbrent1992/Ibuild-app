import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/models/build.dart';
import 'package:ibuild/models/pipeline.dart';

Build _build(BuildStatus status, {List<BuildStep> steps = const []}) => Build(
      id: 'b',
      appId: 'a',
      status: status,
      createdAt: DateTime(2026, 9, 1),
      steps: steps,
    );

void main() {
  group('computePipeline', () {
    test('a queued build is waiting with every station pending', () {
      final snapshot = computePipeline(_build(BuildStatus.queued));
      expect(snapshot.waiting, isTrue);
      for (final station in Station.values) {
        expect(snapshot[station], StationState.pending);
      }
    });

    test('a build running tests has fetched and is testing', () {
      final snapshot = computePipeline(_build(BuildStatus.testing));
      expect(snapshot[Station.fetch], StationState.done);
      expect(snapshot[Station.test], StationState.active);
      expect(snapshot[Station.build], StationState.pending);
    });

    test('a passed build shows TestFlight processing', () {
      final snapshot = computePipeline(
        _build(BuildStatus.finished),
        testFlight: TestFlightState.processing,
      );
      expect(snapshot[Station.upload], StationState.done);
      expect(snapshot[Station.testFlight], StationState.active);
    });

    test('a failed test step stops the line at Test', () {
      final snapshot = computePipeline(_build(BuildStatus.failed, steps: const [
        BuildStep(id: '1', name: 'Fetching app sources', status: 'success'),
        BuildStep(id: '2', name: 'Flutter tests', status: 'failed'),
      ]));
      expect(snapshot[Station.fetch], StationState.done);
      expect(snapshot[Station.test], StationState.failed);
      expect(snapshot[Station.build], StationState.skipped);
      expect(snapshot[Station.testFlight], StationState.skipped);
    });

    test('a workflow without tests marks Test as skipped', () {
      final snapshot = computePipeline(_build(BuildStatus.finished, steps: const [
        BuildStep(id: '1', name: 'Fetching app sources', status: 'success'),
        BuildStep(id: '2', name: 'Flutter build ipa', status: 'success'),
      ]));
      expect(snapshot[Station.test], StationState.skipped);
      expect(snapshot[Station.build], StationState.done);
    });
  });

  test('stationForStep places common Codemagic step names', () {
    expect(stationForStep('Preparing build machine'), Station.fetch);
    expect(stationForStep('Get Flutter packages'), Station.fetch);
    expect(stationForStep('Flutter analyze'), Station.test);
    expect(stationForStep('Set up code signing identities'), Station.build);
    expect(stationForStep('Flutter build ipa'), Station.build);
    expect(stationForStep('Publishing'), Station.upload);
  });

  group('Build.fromCodemagic', () {
    test('reads the legacy response shape', () {
      final build = Build.fromCodemagic({
        'application': {'_id': 'app1'},
        'build': {
          '_id': 'build1',
          'status': 'building',
          'branch': 'main',
          'index': 42,
          'fileWorkflowId': 'ios-testflight',
          'startedAt': '2026-09-01T10:00:00Z',
          'buildActions': [
            {'_id': 's1', 'name': 'Flutter tests', 'status': 'success'},
          ],
          'artefacts': [
            {
              'name': 'app.ipa',
              'url': 'https://api.codemagic.io/artifacts/x/y/app.ipa',
              'size': 1024,
            },
          ],
        },
      });
      expect(build.id, 'build1');
      expect(build.appId, 'app1');
      expect(build.number, 42);
      expect(build.status, BuildStatus.building);
      expect(build.workflowId, 'ios-testflight');
      expect(build.steps.single.name, 'Flutter tests');
      expect(build.artefacts.single.sizeBytes, 1024);
      expect(build.title, 'Build #42');
    });

    test('reads the v3 response shape', () {
      final build = Build.fromCodemagic({
        'data': {'id': 'build2', 'status': 'finished', 'appId': 'app1'},
      });
      expect(build.id, 'build2');
      expect(build.status, BuildStatus.finished);
      expect(build.isInProgress, isFalse);
    });

    test('merging keeps details the fresh copy lacks', () {
      final placeholder = Build.placeholder(
          id: 'b', appId: 'a', workflowId: 'ios-testflight', branch: 'main');
      final merged = placeholder.mergedWith(
          const Build(id: 'b', appId: '', status: BuildStatus.testing));
      expect(merged.status, BuildStatus.testing);
      expect(merged.branch, 'main');
      expect(merged.appId, 'a');
    });
  });
}
