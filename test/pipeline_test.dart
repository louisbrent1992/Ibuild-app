import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/models/build.dart';
import 'package:ibuild/models/pipeline.dart';
import 'package:ibuild/models/project.dart';

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
      expect(snapshot[Station.store], StationState.active);
    });

    test('a failed test step stops the line at Test', () {
      final snapshot = computePipeline(_build(BuildStatus.failed, steps: const [
        BuildStep(id: '1', name: 'Fetching app sources', status: 'success'),
        BuildStep(id: '2', name: 'Flutter tests', status: 'failed'),
      ]));
      expect(snapshot[Station.fetch], StationState.done);
      expect(snapshot[Station.test], StationState.failed);
      expect(snapshot[Station.build], StationState.skipped);
      expect(snapshot[Station.store], StationState.skipped);
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

  group('Android', () {
    test('a finished build has its Play draft done without TestFlight', () {
      final snapshot = computePipeline(
        _build(BuildStatus.finished),
        platform: AppPlatform.android,
      );
      expect(snapshot[Station.store], StationState.done);
      expect(snapshot.platform, AppPlatform.android);
    });

    test('a failed build never reaches Play', () {
      final snapshot = computePipeline(
        _build(BuildStatus.failed, steps: const [
          BuildStep(id: '1', name: 'Build Android App Bundle', status: 'failed'),
        ]),
        platform: AppPlatform.android,
      );
      expect(snapshot[Station.build], StationState.failed);
      expect(snapshot[Station.store], StationState.skipped);
    });

    test('the store station is named for the platform', () {
      expect(Station.store.labelFor(AppPlatform.ios), 'TestFlight');
      expect(Station.store.labelFor(AppPlatform.android), 'Play');
      expect(Station.build.labelFor(AppPlatform.android), 'Build');
    });
  });

  group('Project platform', () {
    Project project(String workflow, {AppPlatform? platform}) => Project(
          id: 'p',
          name: 'P',
          codemagicAppId: 'a',
          workflowId: workflow,
          branch: 'main',
          platform: platform,
        );

    test('is guessed from the workflow key when not stored', () {
      expect(project('android-release').platform, AppPlatform.android);
      expect(project('ios-testflight').platform, AppPlatform.ios);
    });

    test('a stored platform wins and survives JSON', () {
      final p = project('release', platform: AppPlatform.android);
      expect(Project.fromJson(p.toJson()).platform, AppPlatform.android);
    });

    test('projects saved before platforms existed still load', () {
      final old = Project.fromJson(const {
        'id': 'p',
        'name': 'P',
        'codemagicAppId': 'a',
        'workflowId': 'android-release',
        'branch': 'main',
      });
      expect(old.platform, AppPlatform.android);
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
