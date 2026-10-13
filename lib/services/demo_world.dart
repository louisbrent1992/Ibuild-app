import 'dart:math' as math;

import '../models/build.dart';
import '../models/play.dart';
import '../models/project.dart';
import '../models/repo.dart';
import '../models/testflight.dart';
import 'api_client.dart';
import 'app_store_connect_service.dart';
import 'ci_provider.dart';
import 'config_generator.dart';
import 'github_service.dart';
import 'google_play_service.dart';
import 'yaml_parsing.dart';

/// A self-contained pretend Codemagic, GitHub and App Store Connect, so the
/// whole app can be explored before connecting real accounts. Builds move
/// along on the clock; nothing leaves the device.
///
/// Builds on branches starting with `feature/` fail their tests on purpose,
/// so the failure path can be seen too.
class DemoWorld implements CiProvider, SourceHost, StoreConnect, PlayConsole {
  DemoWorld() {
    _seed();
  }

  static const cookbookAppId = 'demo-cookbook';
  static const pantryAppId = 'demo-pantry';

  static const project = Project(
    id: 'demo',
    name: 'Cookbook',
    codemagicAppId: cookbookAppId,
    workflowId: 'ios-testflight',
    branch: 'main',
    repo: 'you/cookbook',
    bundleId: 'com.cookbook.app',
  );

  static const _branches = ['main', 'develop', 'feature/meal-plans'];
  static const _versions = {'main': '2.4.1', 'develop': '2.5.0'};

  final Map<String, _DemoRun> _runs = {};
  final Map<String, String> _written = {};
  final Map<String, BetaGroup> _groups = {
    'internal': const BetaGroup(
        id: 'internal',
        name: 'Internal testers',
        isInternal: true,
        publicLinkEnabled: false),
    'friends': const BetaGroup(
        id: 'friends',
        name: 'Friends and family',
        isInternal: false,
        publicLinkEnabled: false),
  };
  int _nextNumber = 87;

  void _seed() {
    final now = DateTime.now();
    // Scaled so a 40-second demo build reads as 4m 32s in history.
    const scale = 6.8;
    _runs['demo-84'] = _DemoRun(
        id: 'demo-84',
        appId: cookbookAppId,
        number: 84,
        branch: 'main',
        workflowId: 'ios-testflight',
        startedAt: now.subtract(const Duration(days: 3, hours: 2)),
        message: 'Add pantry sync',
        scale: scale);
    _runs['demo-85'] = _DemoRun(
        id: 'demo-85',
        appId: cookbookAppId,
        number: 85,
        branch: 'feature/meal-plans',
        workflowId: 'ios-testflight',
        startedAt: now.subtract(const Duration(days: 1, hours: 5)),
        message: 'Weekly meal plan totals',
        failsTests: true,
        scale: scale);
    _runs['demo-86'] = _DemoRun(
        id: 'demo-86',
        appId: cookbookAppId,
        number: 86,
        branch: 'main',
        workflowId: 'ios-testflight',
        startedAt: now.subtract(const Duration(hours: 6)),
        message: 'Fix meal plan calorie rounding',
        scale: scale);
  }

  Future<void> _pause([int ms = 250]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  String _versionFor(String? branch) => _versions[branch] ?? '2.5.0';

  // ---------------------------------------------------------------- CI

  @override
  String get name => 'Demo';

  @override
  Future<List<CiApp>> listApps() async {
    await _pause();
    return const [
      CiApp(id: cookbookAppId, name: 'Cookbook', branches: _branches),
      CiApp(id: pantryAppId, name: 'Pantry Scanner', branches: ['main']),
    ];
  }

  @override
  Future<String> startBuild({
    required String appId,
    required String workflowId,
    required String branch,
  }) async {
    await _pause(400);
    final number = _nextNumber++;
    final id = 'demo-$number';
    _runs[id] = _DemoRun(
      id: id,
      appId: appId,
      number: number,
      branch: branch,
      workflowId: workflowId,
      startedAt: DateTime.now(),
      message: 'Started from iBuild',
      failsTests: branch.startsWith('feature/'),
    );
    return id;
  }

  @override
  Future<Build> getBuild(String buildId) async {
    await _pause(120);
    final run = _runs[buildId];
    if (run == null) {
      throw ApiException('Demo', 'There is no demo build with ID $buildId.',
          statusCode: 404);
    }
    return _snapshot(run);
  }

  @override
  Future<List<Build>> listBuilds({required String appId}) async {
    await _pause();
    final runs = _runs.values.where((r) => r.appId == appId).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return [for (final run in runs) _snapshot(run)];
  }

  @override
  Future<void> cancelBuild(String buildId) async {
    await _pause();
    final run = _runs[buildId];
    if (run == null) return;
    final elapsed = run.elapsed(DateTime.now());
    if (elapsed < run.endAt) run.canceledAt = elapsed;
  }

  @override
  Future<String?> fetchStepLog(Build build, BuildStep step) async {
    await _pause(80);
    return step.inlineLog;
  }

  @override
  Future<Uri?> downloadUrl(Artefact artefact) async => null;

  @override
  Uri? webUrl(Build build) => null;

  Build _snapshot(_DemoRun run) {
    final now = DateTime.now();
    final elapsed = run.elapsed(now);
    final end = run.endAt;
    final done = elapsed >= end;
    final t = math.min(elapsed, end);

    final BuildStatus status;
    if (done) {
      status = run.canceled
          ? BuildStatus.canceled
          : run.failsTests
              ? BuildStatus.failed
              : BuildStatus.finished;
    } else {
      status = _statusAt.lastWhere((entry) => t >= entry.$1).$2;
    }

    final steps = <BuildStep>[];
    for (var i = 0; i < _plan.length; i++) {
      final plan = _plan[i];
      if (t < plan.start) break;
      final finished = t >= plan.end;
      final failedHere = done && !run.canceled && run.failsTests && !finished;
      final canceledHere = done && run.canceled && !finished;
      final progress = ((t - plan.start) / (plan.end - plan.start)).clamp(0.0, 1.0);
      final lines = failedHere && plan.failLines != null
          ? plan.failLines!
          : plan.lines
              .take(math.max(1, (plan.lines.length * progress).ceil()))
              .toList();
      steps.add(BuildStep(
        id: 'step-$i',
        name: plan.name,
        status: failedHere
            ? 'failed'
            : canceledHere
                ? 'canceled'
                : finished
                    ? 'success'
                    : 'running',
        startedAt: run.at(plan.start),
        finishedAt: finished || failedHere || canceledHere
            ? run.at(math.min(t, plan.end))
            : null,
        inlineLog: [
          ...lines,
          if (canceledHere) 'Build canceled from iBuild.',
        ].join('\n'),
      ));
      if (failedHere || canceledHere) break;
    }

    return Build(
      id: run.id,
      appId: run.appId,
      status: status,
      workflowId: run.workflowId,
      branch: run.branch,
      number: run.number,
      createdAt: run.startedAt,
      startedAt: elapsed >= 3 ? run.at(3) : null,
      finishedAt: done ? run.at(end) : null,
      steps: steps,
      artefacts: status != BuildStatus.finished
          ? const []
          : _isAndroid(run)
              ? [
                  Artefact(
                      name: 'app-release.aab',
                      url: 'demo://app-release.aab',
                      type: 'aab',
                      sizeBytes: 31457280,
                      versionCode: run.number),
                ]
              : const [
                  Artefact(
                      name: 'Cookbook.ipa',
                      url: 'demo://Cookbook.ipa',
                      type: 'ipa',
                      sizeBytes: 48213504),
                ],
      message: run.message,
    );
  }

  // ------------------------------------------------------------ Source

  @override
  Future<String> currentUser() async => 'you';

  @override
  Future<List<GitHubRepo>> listRepos() async {
    await _pause();
    return const [
      GitHubRepo(fullName: 'you/cookbook', defaultBranch: 'main', isPrivate: true),
      GitHubRepo(fullName: 'you/pantry-scanner', defaultBranch: 'main'),
    ];
  }

  @override
  Future<List<String>> listBranches(String repo) async {
    await _pause();
    return repo == 'you/cookbook' ? _branches : const ['main'];
  }

  @override
  Future<String?> readFile(String repo, String path, {String? ref}) async {
    await _pause(150);
    if (path == 'pubspec.yaml') {
      final name = repo.split('/').last.replaceAll('-', '_');
      return 'name: $name\nversion: ${_versionFor(ref ?? 'main')}+${_nextNumber - 1}\n';
    }
    if (path == 'codemagic.yaml') {
      return _written[repo] ??
          (repo == 'you/cookbook'
              ? generateCodemagicYaml(const ConfigOptions(
                  ios: true, android: true, bundleId: 'com.cookbook.app'))
              : null);
    }
    return null;
  }

  @override
  Future<void> writeFile(
    String repo,
    String path,
    String content, {
    required String message,
    String? branch,
  }) async {
    await _pause(500);
    if (path == 'codemagic.yaml') _written[repo] = content;
  }

  @override
  Future<ProjectDetection> detect(String repo, {String? ref}) async {
    final pubspec = parsePubspec(await readFile(repo, 'pubspec.yaml', ref: ref) ?? '');
    final yaml = await readFile(repo, 'codemagic.yaml', ref: ref);
    final codemagic = yaml == null ? const CodemagicInfo() : parseCodemagicYaml(yaml);
    return ProjectDetection(
      hasPubspec: true,
      hasIos: true,
      hasAndroid: true,
      hasCodemagicYaml: yaml != null,
      appName: pubspec.name,
      version: pubspec.version,
      workflows: codemagic.workflows,
      androidWorkflows: codemagic.androidWorkflows,
      bundleId: codemagic.bundleId,
    );
  }

  // ------------------------------------------------------ App Store

  @override
  Future<void> verify() async {}

  @override
  Future<String?> findAppId(String bundleId) async {
    await _pause();
    return '6448912345';
  }

  @override
  Future<List<TestFlightBuild>> recentBuilds(String appId) async {
    await _pause();
    final now = DateTime.now();
    final list = <TestFlightBuild>[];
    for (final run in _runs.values) {
      if (run.appId != cookbookAppId || run.endAt < _uploadDoneAt) continue;
      final uploadedAt = run.at(_uploadDoneAt);
      if (now.isBefore(uploadedAt)) continue;
      final processedAt =
          uploadedAt.add(Duration(milliseconds: (20000 * run.scale).round()));
      list.add(TestFlightBuild(
        id: 'tf-${run.number}',
        buildNumber: '${run.number}',
        version: _versionFor(run.branch),
        processingState: now.isAfter(processedAt) ? 'VALID' : 'PROCESSING',
        uploadedAt: uploadedAt,
      ));
    }
    list.sort((a, b) => b.uploadedAt!.compareTo(a.uploadedAt!));
    return list;
  }

  @override
  Future<List<BetaGroup>> betaGroups(String appId) async {
    await _pause();
    return _groups.values.toList();
  }

  static bool _isAndroid(_DemoRun run) =>
      platformForWorkflow(run.workflowId) == AppPlatform.android;

  @override
  Future<PlaySnapshot> snapshot(String packageName) async {
    await _pause();
    final now = DateTime.now();
    final built = _runs.values
        .where((r) => _isAndroid(r) && !r.failsTests && !r.canceled && now.isAfter(r.at(_uploadDoneAt)))
        .toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    return PlaySnapshot(
      releases: [
        const PlayRelease(
            track: 'production',
            status: PlayReleaseStatus.completed,
            name: '82 (2.4.0)',
            versionCodes: [82]),
        for (final run in built.take(3))
          PlayRelease(
            track: 'alpha',
            status: PlayReleaseStatus.draft,
            name: '${run.number} (${_versionFor(run.branch)})',
            versionCodes: [run.number],
          ),
      ],
      testerGroups: const {
        'alpha': ['cookbook-testers@googlegroups.com'],
      },
    );
  }

  @override
  Future<BetaGroup> enablePublicLink(BetaGroup group) async {
    await _pause(500);
    final updated = group.copyWith(
      publicLinkEnabled: true,
      publicLink: 'https://testflight.apple.com/join/DeMo${group.id.hashCode.abs() % 10000}',
    );
    _groups[group.id] = updated;
    return updated;
  }
}

// Demo build timeline, in seconds from the moment the build is started.
const _statusAt = <(double, BuildStatus)>[
  (0.0, BuildStatus.queued),
  (3.0, BuildStatus.preparing),
  (7.0, BuildStatus.fetching),
  (11.0, BuildStatus.testing),
  (19.0, BuildStatus.building),
  (31.0, BuildStatus.publishing),
  (37.0, BuildStatus.finishing),
];
const _totalSeconds = 40.0;
const _uploadDoneAt = 37.0;
const _testFailAt = 15.5;

class _DemoRun {
  _DemoRun({
    required this.id,
    required this.appId,
    required this.number,
    required this.branch,
    required this.workflowId,
    required this.startedAt,
    required this.message,
    this.failsTests = false,
    this.scale = 1.0,
  });

  final String id;
  final String appId;
  final int number;
  final String branch;
  final String workflowId;
  final DateTime startedAt;
  final String message;
  final bool failsTests;

  /// Stretches the timeline; seeded history uses it to look realistic.
  final double scale;
  double? canceledAt;

  bool get canceled => canceledAt != null;

  double get endAt => canceledAt ?? (failsTests ? _testFailAt : _totalSeconds);

  double elapsed(DateTime now) =>
      now.difference(startedAt).inMilliseconds / 1000 / scale;

  DateTime at(double seconds) =>
      startedAt.add(Duration(milliseconds: (seconds * scale * 1000).round()));
}

class _StepPlan {
  const _StepPlan(this.name, this.start, this.end, this.lines, {this.failLines});

  final String name;
  final double start;
  final double end;
  final List<String> lines;
  final List<String>? failLines;
}

const _plan = <_StepPlan>[
  _StepPlan('Preparing build machine', 3.0, 7.0, [
    'Requesting a Mac mini M2',
    'Machine assigned in eu-west',
    'Xcode 26.6 selected',
    'Build machine ready',
  ]),
  _StepPlan('Fetching app sources', 7.0, 9.0, [
    'git clone --depth 50 git@github.com:you/cookbook.git',
    'Checked out the requested branch',
    'HEAD is 4f2a9c1 Fix meal plan calorie rounding',
  ]),
  _StepPlan('Get Flutter packages', 9.0, 11.0, [
    'flutter pub get',
    'Resolving dependencies...',
    'Got dependencies!',
  ]),
  _StepPlan('Flutter tests', 11.0, 19.0, [
    'flutter test',
    '00:02 +12: loading test/recipe_parser_test.dart',
    '00:05 +38: ingredient parser handles fractions',
    '00:07 +64: meal plan totals calories across days',
    '00:08 +71: All tests passed!',
  ], failLines: [
    'flutter test',
    '00:02 +12: loading test/recipe_parser_test.dart',
    '00:05 +38: ingredient parser handles fractions',
    '00:06 +40 -1: meal plan totals calories across days [E]',
    '  Expected: <2150>',
    '    Actual: <2100>',
    '00:07 +43 -1: Some tests failed.',
  ]),
  _StepPlan('Set up code signing identities', 19.0, 22.0, [
    'Fetching signing files for com.cookbook.app',
    'Using profile "Cookbook App Store"',
    'Keychain ready',
  ]),
  _StepPlan('Flutter build ipa', 22.0, 31.0, [
    'flutter build ipa --release',
    'Running pod install...',
    'Archiving com.cookbook.app...',
    'Built build/ios/archive/Runner.xcarchive (212.4MB)',
    'Building App Store IPA...',
    'Built IPA to build/ios/ipa (46.0MB)',
  ]),
  _StepPlan('Publishing to App Store Connect', 31.0, 37.0, [
    'Uploading Cookbook.ipa to App Store Connect',
    'Upload progress 48%',
    'Upload progress 100%',
    'Uploaded. Apple is now processing the build.',
    'Added to TestFlight group "App testers"',
  ]),
  _StepPlan('Cleaning up', 37.0, 40.0, [
    'Saving caches',
    'Build machine released',
  ]),
];
