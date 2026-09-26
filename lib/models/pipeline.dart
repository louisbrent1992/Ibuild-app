import 'build.dart';

/// The stations on the line a build travels, from source to testers.
enum Station {
  fetch('Fetch'),
  test('Test'),
  build('Build'),
  upload('Upload'),
  testFlight('TestFlight');

  const Station(this.label);
  final String label;
}

enum StationState { pending, active, done, failed, skipped }

enum TestFlightState { unknown, notConfigured, processing, ready, failed }

/// Stations that the CI provider reports on (TestFlight comes from Apple).
const ciStations = [Station.fetch, Station.test, Station.build, Station.upload];

Station? stationForStatus(BuildStatus status) => switch (status) {
      BuildStatus.preparing || BuildStatus.fetching => Station.fetch,
      BuildStatus.testing => Station.test,
      BuildStatus.building => Station.build,
      BuildStatus.publishing || BuildStatus.finishing => Station.upload,
      _ => null,
    };

/// Places a free-form step name such as "Set up code signing identities"
/// on the line. Order matters: "Preparing build machine" is a fetch step.
Station stationForStep(String stepName) {
  final name = stepName.toLowerCase();
  bool has(List<String> words) => words.any(name.contains);
  if (has(['test', 'analy', 'lint'])) return Station.test;
  if (has(['publish', 'upload', 'app store', 'testflight', 'clean'])) {
    return Station.upload;
  }
  if (has(['prepar', 'fetch', 'clone', 'install', 'package', 'sdk', 'cache', 'pod'])) {
    return Station.fetch;
  }
  return Station.build;
}

class PipelineSnapshot {
  const PipelineSnapshot(this.states, {this.waiting = false});

  final Map<Station, StationState> states;

  /// True while the build is queued and no machine has picked it up.
  final bool waiting;

  StationState operator [](Station station) =>
      states[station] ?? StationState.pending;
}

PipelineSnapshot computePipeline(
  Build? build, {
  TestFlightState testFlight = TestFlightState.unknown,
  Station? lastSeen,
}) {
  final states = {for (final s in Station.values) s: StationState.pending};
  if (build == null) return PipelineSnapshot(states);

  final stepStations = build.steps.map((s) => stationForStep(s.name)).toSet();
  final testsRan = build.steps.isEmpty || stepStations.contains(Station.test);

  void markThrough(Station reached, StationState atReached, StationState after) {
    for (final s in ciStations) {
      if (s.index < reached.index) {
        states[s] = StationState.done;
      } else if (s == reached) {
        states[s] = atReached;
      } else {
        states[s] = after;
      }
    }
    if (!testsRan && reached.index > Station.test.index) {
      states[Station.test] = StationState.skipped;
    }
  }

  if (build.isInProgress) {
    final runningStep = build.steps.where((s) => s.isRunning).firstOrNull;
    final current = stationForStatus(build.status) ??
        (runningStep == null ? null : stationForStep(runningStep.name));
    if (current == null) return PipelineSnapshot(states, waiting: true);
    markThrough(current, StationState.active, StationState.pending);
    return PipelineSnapshot(states);
  }

  switch (build.status) {
    case BuildStatus.finished:
      for (final s in ciStations) {
        states[s] = StationState.done;
      }
      if (!testsRan) states[Station.test] = StationState.skipped;
      states[Station.testFlight] = switch (testFlight) {
        TestFlightState.ready => StationState.done,
        TestFlightState.processing => StationState.active,
        TestFlightState.failed => StationState.failed,
        TestFlightState.notConfigured => StationState.skipped,
        TestFlightState.unknown => StationState.pending,
      };
    case BuildStatus.failed || BuildStatus.timeout:
      final failedStep = build.steps.where((s) => s.hasFailed).firstOrNull;
      final at = failedStep != null ? stationForStep(failedStep.name) : lastSeen;
      if (at != null) {
        markThrough(at, StationState.failed, StationState.skipped);
      }
      states[Station.testFlight] = StationState.skipped;
    default:
      for (final s in ciStations) {
        states[s] = lastSeen != null && s.index < lastSeen.index
            ? StationState.done
            : StationState.skipped;
      }
      states[Station.testFlight] = StationState.skipped;
  }
  return PipelineSnapshot(states);
}
