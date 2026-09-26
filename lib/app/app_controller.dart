import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/build.dart';
import '../models/pipeline.dart';
import '../models/project.dart';
import '../models/testflight.dart';
import '../services/api_client.dart';
import '../services/app_store_connect_service.dart';
import '../services/ci_provider.dart';
import '../services/codemagic_service.dart';
import '../services/demo_world.dart';
import '../services/github_service.dart';
import '../services/yaml_parsing.dart';

enum Connection { codemagic, github, appStoreConnect }

/// Holds credentials, projects and live build state for the whole app.
class AppController extends ChangeNotifier {
  AppController({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _kDemo = 'demo_mode';
  static const _kCodemagic = 'codemagic_token';
  static const _kGitHub = 'github_token';
  static const _kIssuer = 'asc_issuer_id';
  static const _kKeyId = 'asc_key_id';
  static const _kPrivateKey = 'asc_private_key';
  static const _kProjects = 'projects';
  static const _kSelected = 'selected_project';

  final FlutterSecureStorage _storage;
  final DemoWorld _demo = DemoWorld();

  bool _demoMode = true;
  String? _codemagicToken;
  String? _githubToken;
  String? _ascIssuerId;
  String? _ascKeyId;
  String? _ascPrivateKey;

  CiProvider? _ci;
  SourceHost? _source;
  StoreConnect? _store;

  List<Project> _projects = [];
  Project _demoProject = DemoWorld.project;
  final List<Project> _demoExtras = [];
  String? _selectedProjectId;
  final Map<String, String> _branchOverride = {};

  List<Build> _builds = [];
  final Map<String, Build> _cache = {};
  final Set<String> _watched = {};
  final Map<String, Station> _lastSeen = {};
  int _generation = 0;

  bool loadingBuilds = false;
  String? buildsError;
  String? pollError;
  bool starting = false;

  String? versionLabel;
  bool loadingVersion = false;

  List<TestFlightBuild> testFlightBuilds = [];
  bool loadingTestFlight = false;
  String? testFlightError;
  String? _ascAppId;
  String? _ascAppBundle;

  List<BetaGroup> betaGroups = [];
  bool loadingBetaGroups = false;
  String? betaGroupsError;

  Timer? _ticker;
  int _ticks = 0;
  bool _polling = false;

  // ------------------------------------------------------------ Reading

  bool get demoMode => _demoMode;
  bool get hasCodemagic => (_codemagicToken ?? '').isNotEmpty;
  bool get hasGitHub => (_githubToken ?? '').isNotEmpty;
  bool get hasAppStoreConnect =>
      (_ascIssuerId ?? '').isNotEmpty &&
      (_ascKeyId ?? '').isNotEmpty &&
      (_ascPrivateKey ?? '').isNotEmpty;
  String get ascIssuerId => _ascIssuerId ?? '';
  String get ascKeyId => _ascKeyId ?? '';

  CiProvider? get ci => _demoMode ? _demo : _ci;
  SourceHost? get source => _demoMode ? _demo : _source;
  StoreConnect? get store => _demoMode ? _demo : _store;

  List<Project> get projects => _demoMode
      ? [_demoProject, ..._demoExtras]
      : List.unmodifiable(_projects);

  Project? get project {
    final list = projects;
    if (list.isEmpty) return null;
    return list.where((p) => p.id == _selectedProjectId).firstOrNull ??
        list.first;
  }

  String get branch {
    final p = project;
    if (p == null) return 'main';
    return _branchOverride[p.id] ?? p.branch;
  }

  List<Build> get builds => List.unmodifiable(_builds);
  Build? get latestBuild => _builds.firstOrNull;
  Build? buildById(String id) => _cache[id];
  Station? lastSeenStation(String id) => _lastSeen[id];

  /// Matches a CI build to the first App Store Connect upload after it began.
  TestFlightState testFlightStateFor(Build? build) {
    final p = project;
    if (store == null || p == null || (p.bundleId ?? '').isEmpty) {
      return TestFlightState.notConfigured;
    }
    if (build == null) return TestFlightState.unknown;
    final since = build.startedAt ?? build.createdAt;
    if (since == null) return TestFlightState.unknown;
    final uploads = testFlightBuilds
        .where((t) => t.uploadedAt != null && t.uploadedAt!.isAfter(since))
        .toList()
      ..sort((a, b) => a.uploadedAt!.compareTo(b.uploadedAt!));
    return uploads.isEmpty ? TestFlightState.unknown : uploads.first.state;
  }

  // ------------------------------------------------------------ Storage

  Future<void> load() async {
    try {
      final values = await _storage.readAll();
      _demoMode = values[_kDemo] != 'false';
      _codemagicToken = values[_kCodemagic];
      _githubToken = values[_kGitHub];
      _ascIssuerId = values[_kIssuer];
      _ascKeyId = values[_kKeyId];
      _ascPrivateKey = values[_kPrivateKey];
      _selectedProjectId = values[_kSelected];
      final raw = values[_kProjects];
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _projects = decoded
              .whereType<Map>()
              .map((m) => Project.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Could not read saved settings: $e');
    }
    _rebuildServices();
    notifyListeners();
    unawaited(refreshAll());
  }

  Future<void> _write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<void> _saveProjects() => _storage.write(
        key: _kProjects,
        value: jsonEncode(_projects.map((p) => p.toJson()).toList()),
      );

  void _rebuildServices() {
    final codemagic = _codemagicToken;
    final github = _githubToken;
    _ci = codemagic != null && codemagic.isNotEmpty
        ? CodemagicService(codemagic)
        : null;
    _source =
        github != null && github.isNotEmpty ? GitHubService(github) : null;
    _store = hasAppStoreConnect
        ? AppStoreConnectService(
            issuerId: _ascIssuerId!,
            keyId: _ascKeyId!,
            privateKey: _ascPrivateKey!,
          )
        : null;
  }

  void _resetData() {
    _generation++;
    _stopTicker();
    _builds = [];
    _cache.clear();
    _watched.clear();
    _lastSeen.clear();
    buildsError = null;
    pollError = null;
    versionLabel = null;
    testFlightBuilds = [];
    testFlightError = null;
    betaGroups = [];
    betaGroupsError = null;
    _ascAppId = null;
    _ascAppBundle = null;
  }

  // -------------------------------------------------------- Connections

  Future<void> setDemoMode(bool value) async {
    if (_demoMode == value) return;
    _demoMode = value;
    await _write(_kDemo, value ? 'true' : 'false');
    _resetData();
    notifyListeners();
    unawaited(refreshAll());
  }

  /// Checks the token with Codemagic before saving it. Returns a short
  /// confirmation, or throws [ApiException].
  Future<String> connectCodemagic(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      throw ApiException('Codemagic', 'Paste your Codemagic API token first.');
    }
    final apps = await CodemagicService(value).listApps();
    _codemagicToken = value;
    await _write(_kCodemagic, value);
    _rebuildServices();
    if (_demoMode) {
      await setDemoMode(false);
    } else {
      _resetData();
      notifyListeners();
      unawaited(refreshAll());
    }
    return 'Connected. Codemagic lists ${apps.length} ${apps.length == 1 ? 'app' : 'apps'}.';
  }

  Future<String> connectGitHub(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      throw ApiException('GitHub', 'Paste a GitHub token first.');
    }
    final login = await GitHubService(value).currentUser();
    _githubToken = value;
    await _write(_kGitHub, value);
    _rebuildServices();
    notifyListeners();
    unawaited(refreshVersion());
    return 'Connected as $login.';
  }

  /// Leaving [privateKey] empty keeps the key that is already saved.
  Future<String> connectAppStore({
    required String issuerId,
    required String keyId,
    String? privateKey,
  }) async {
    final issuer = issuerId.trim();
    final key = keyId.trim();
    final pasted = privateKey?.trim() ?? '';
    final secret = pasted.isNotEmpty ? pasted : (_ascPrivateKey ?? '');
    if (issuer.isEmpty || key.isEmpty || secret.isEmpty) {
      throw ApiException('App Store Connect',
          'Fill in the issuer ID, key ID and private key.');
    }
    await AppStoreConnectService(issuerId: issuer, keyId: key, privateKey: secret)
        .verify();
    _ascIssuerId = issuer;
    _ascKeyId = key;
    _ascPrivateKey = secret;
    await _write(_kIssuer, issuer);
    await _write(_kKeyId, key);
    await _write(_kPrivateKey, secret);
    _rebuildServices();
    _ascAppId = null;
    _ascAppBundle = null;
    notifyListeners();
    unawaited(refreshTestFlight());
    return 'Connected to App Store Connect.';
  }

  Future<void> disconnect(Connection connection) async {
    switch (connection) {
      case Connection.codemagic:
        _codemagicToken = null;
        await _write(_kCodemagic, null);
      case Connection.github:
        _githubToken = null;
        await _write(_kGitHub, null);
      case Connection.appStoreConnect:
        _ascIssuerId = null;
        _ascKeyId = null;
        _ascPrivateKey = null;
        await _write(_kIssuer, null);
        await _write(_kKeyId, null);
        await _write(_kPrivateKey, null);
    }
    _rebuildServices();
    _resetData();
    notifyListeners();
    unawaited(refreshAll());
  }

  // ----------------------------------------------------------- Projects

  Future<void> addProject(Project added) async {
    if (_demoMode) {
      _demoExtras.add(added);
    } else {
      _projects = [..._projects, added];
      await _saveProjects();
    }
    await selectProject(added.id);
  }

  Future<void> updateProject(Project updated) async {
    if (_demoMode) {
      if (updated.id == _demoProject.id) {
        _demoProject = updated;
      } else {
        final index = _demoExtras.indexWhere((p) => p.id == updated.id);
        if (index >= 0) _demoExtras[index] = updated;
      }
    } else {
      _projects = [
        for (final p in _projects) p.id == updated.id ? updated : p,
      ];
      await _saveProjects();
    }
    if (updated.id == project?.id) {
      _ascAppId = null;
      _ascAppBundle = null;
      unawaited(refreshVersion());
      unawaited(refreshTestFlight());
    }
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    if (_demoMode) {
      _demoExtras.removeWhere((p) => p.id == id);
    } else {
      _projects = _projects.where((p) => p.id != id).toList();
      await _saveProjects();
    }
    if (_selectedProjectId == id) {
      _selectedProjectId = null;
      _resetData();
      unawaited(refreshAll());
    }
    notifyListeners();
  }

  Future<void> selectProject(String id) async {
    _selectedProjectId = id;
    if (!_demoMode) await _write(_kSelected, id);
    _resetData();
    notifyListeners();
    await refreshAll();
  }

  void selectBranch(String name) {
    final p = project;
    if (p == null) return;
    _branchOverride[p.id] = name;
    notifyListeners();
    unawaited(refreshVersion());
  }

  /// Workflow keys from the repository's codemagic.yaml, plus any Workflow
  /// Editor workflows Codemagic reports for the app.
  Future<List<String>> workflowsFor(Project p) async {
    final found = <String>{};
    final src = source;
    final repo = p.repo;
    if (src != null && repo != null) {
      final yaml = await src.readFile(repo, 'codemagic.yaml', ref: branch);
      if (yaml != null) found.addAll(parseCodemagicYaml(yaml).workflows);
    }
    final provider = ci;
    if (provider != null) {
      final apps = await provider.listApps();
      for (final app in apps.where((a) => a.id == p.codemagicAppId)) {
        found.addAll(app.workflows.keys);
      }
    }
    return found.toList();
  }

  // ---------------------------------------------------------- Refreshing

  Future<void> refreshAll() async {
    await Future.wait([refreshBuilds(), refreshVersion(), refreshTestFlight()]);
  }

  Future<void> refreshBuilds() async {
    final p = project;
    final provider = ci;
    if (p == null || provider == null) {
      _builds = [];
      buildsError = null;
      notifyListeners();
      return;
    }
    final generation = _generation;
    loadingBuilds = true;
    notifyListeners();
    try {
      final fetched = await provider.listBuilds(appId: p.codemagicAppId);
      if (generation != _generation) return;
      final merged = [for (final b in fetched) _absorb(b)];
      final pending = _builds.where((b) =>
          b.isInProgress &&
          b.appId == p.codemagicAppId &&
          !merged.any((m) => m.id == b.id));
      _builds = [...pending, ...merged];
      buildsError = null;
    } catch (e) {
      if (generation == _generation) buildsError = e.toString();
    } finally {
      loadingBuilds = false;
      _updateTicker();
      notifyListeners();
    }
  }

  Future<void> refreshVersion() async {
    final p = project;
    final src = source;
    final repo = p?.repo;
    if (p == null || src == null || repo == null) {
      versionLabel = null;
      notifyListeners();
      return;
    }
    final branchAtStart = branch;
    final generation = _generation;
    loadingVersion = true;
    notifyListeners();
    try {
      final text = await src.readFile(repo, 'pubspec.yaml', ref: branchAtStart);
      if (generation != _generation || branch != branchAtStart) return;
      versionLabel =
          text == null ? null : formatVersion(parsePubspec(text).version);
    } catch (_) {
      versionLabel = null;
    } finally {
      loadingVersion = false;
      notifyListeners();
    }
  }

  Future<void> refreshTestFlight({bool notify = true}) async {
    final p = project;
    final s = store;
    if (p == null || s == null || (p.bundleId ?? '').isEmpty) {
      testFlightBuilds = [];
      testFlightError = null;
      if (notify) notifyListeners();
      return;
    }
    final generation = _generation;
    loadingTestFlight = true;
    if (notify) notifyListeners();
    try {
      final appId = await _appStoreAppId(p, s);
      if (generation != _generation) return;
      if (appId == null) {
        testFlightBuilds = [];
        testFlightError =
            'App Store Connect has no app with bundle ID ${p.bundleId}.';
        return;
      }
      final list = await s.recentBuilds(appId);
      if (generation != _generation) return;
      testFlightBuilds = list;
      testFlightError = null;
    } catch (e) {
      if (generation == _generation) testFlightError = e.toString();
    } finally {
      loadingTestFlight = false;
      _updateTicker();
      if (notify) notifyListeners();
    }
  }

  Future<void> loadBetaGroups() async {
    final p = project;
    final s = store;
    if (p == null || s == null || (p.bundleId ?? '').isEmpty) {
      betaGroups = [];
      betaGroupsError = null;
      notifyListeners();
      return;
    }
    final generation = _generation;
    loadingBetaGroups = true;
    notifyListeners();
    try {
      final appId = await _appStoreAppId(p, s);
      final groups = appId == null ? <BetaGroup>[] : await s.betaGroups(appId);
      if (generation != _generation) return;
      betaGroups = groups;
      betaGroupsError = null;
    } catch (e) {
      if (generation == _generation) betaGroupsError = e.toString();
    } finally {
      loadingBetaGroups = false;
      notifyListeners();
    }
  }

  Future<String?> _appStoreAppId(Project p, StoreConnect s) async {
    final bundleId = p.bundleId!;
    if (_ascAppBundle == bundleId && _ascAppId != null) return _ascAppId;
    final id = await s.findAppId(bundleId);
    _ascAppBundle = bundleId;
    _ascAppId = id;
    return id;
  }

  // ------------------------------------------------------------ Actions

  Future<Build> startBuild({String? branchOverride, String? workflowOverride}) async {
    final p = project;
    final provider = ci;
    if (p == null || provider == null) {
      throw ApiException(
          'iBuild', 'Connect Codemagic and add a project before building.');
    }
    final branchName = branchOverride ?? branch;
    final workflow = workflowOverride ?? p.workflowId;
    starting = true;
    notifyListeners();
    try {
      final id = await provider.startBuild(
        appId: p.codemagicAppId,
        workflowId: workflow,
        branch: branchName,
      );
      _remember(Build.placeholder(
        id: id,
        appId: p.codemagicAppId,
        workflowId: workflow,
        branch: branchName,
      ));
      _watched.add(id);
      try {
        _remember(await provider.getBuild(id));
      } catch (_) {
        // The poller will fill in details on its next pass.
      }
      _updateTicker();
      return _cache[id]!;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> cancelBuild(String id) async {
    final provider = ci;
    if (provider == null) return;
    await provider.cancelBuild(id);
    try {
      _remember(await provider.getBuild(id));
    } catch (_) {
      // The poller will pick up the new status.
    }
    _updateTicker();
    notifyListeners();
  }

  Future<BetaGroup> enablePublicLink(BetaGroup group) async {
    final s = store;
    if (s == null) {
      throw ApiException('App Store Connect', 'Connect App Store Connect first.');
    }
    final updated = await s.enablePublicLink(group);
    betaGroups = [for (final g in betaGroups) g.id == group.id ? updated : g];
    notifyListeners();
    return updated;
  }

  /// Keeps a build's details fresh while a screen is showing it.
  void watch(String id) {
    _watched.add(id);
    if (!_cache.containsKey(id)) unawaited(_fetchOnce(id));
    _updateTicker();
  }

  void unwatch(String id) => _watched.remove(id);

  Future<void> _fetchOnce(String id) async {
    final provider = ci;
    if (provider == null) return;
    final generation = _generation;
    try {
      final fresh = await provider.getBuild(id);
      if (generation != _generation) return;
      _remember(fresh);
      pollError = null;
    } catch (e) {
      pollError = e.toString();
    }
    notifyListeners();
  }

  Future<String?> fetchStepLog(Build build, BuildStep step) async {
    final provider = ci;
    if (provider == null) return null;
    return provider.fetchStepLog(build, step);
  }

  Future<Uri?> downloadUrl(Artefact artefact) async {
    final provider = ci;
    if (provider == null) return null;
    return provider.downloadUrl(artefact);
  }

  Uri? webUrl(Build build) => ci?.webUrl(build);

  // ------------------------------------------------------------ Polling

  Build _absorb(Build fresh) {
    final previous = _cache[fresh.id];
    final merged = previous == null ? fresh : previous.mergedWith(fresh);
    _cache[fresh.id] = merged;
    final station = stationForStatus(merged.status);
    if (station != null) _lastSeen[merged.id] = station;
    return merged;
  }

  void _remember(Build fresh) {
    final previous = _cache[fresh.id];
    final merged = _absorb(fresh);
    final index = _builds.indexWhere((b) => b.id == merged.id);
    if (index >= 0) {
      _builds[index] = merged;
    } else if (merged.appId == project?.codemagicAppId) {
      _builds.insert(0, merged);
    }
    final justFinished = previous != null &&
        previous.isInProgress &&
        !merged.isInProgress &&
        merged.status == BuildStatus.finished;
    if (justFinished) unawaited(refreshTestFlight());
  }

  /// True for a little while after a build passes, until Apple reports the
  /// upload (workflows that do not publish simply stop being checked).
  bool get _awaitingTestFlight {
    final p = project;
    if (store == null || p == null || (p.bundleId ?? '').isEmpty) return false;
    final latest = latestBuild;
    if (latest == null || latest.status != BuildStatus.finished) return false;
    final state = testFlightStateFor(latest);
    if (state == TestFlightState.processing) return true;
    final finished = latest.finishedAt;
    return state == TestFlightState.unknown &&
        finished != null &&
        DateTime.now().difference(finished) < const Duration(minutes: 30);
  }

  bool get _needsTicking =>
      _builds.any((b) => b.isInProgress) ||
      _watched.any((id) => _cache[id]?.isInProgress ?? true) ||
      testFlightBuilds.any((t) => t.state == TestFlightState.processing) ||
      _awaitingTestFlight;

  void _updateTicker() {
    if (!_needsTicking) {
      _stopTicker();
      return;
    }
    _ticker ??= Timer.periodic(
      _demoMode ? const Duration(seconds: 1) : const Duration(seconds: 5),
      (_) => _tick(),
    );
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _tick() async {
    if (_polling) return;
    _polling = true;
    _ticks++;
    final generation = _generation;
    try {
      final provider = ci;
      if (provider != null) {
        final ids = <String>{
          ..._builds.where((b) => b.isInProgress).map((b) => b.id),
          ..._watched.where((id) => _cache[id]?.isInProgress ?? true),
        };
        for (final id in ids) {
          try {
            final fresh = await provider.getBuild(id);
            if (generation != _generation) return;
            _remember(fresh);
            pollError = null;
          } catch (e) {
            pollError = e.toString();
          }
        }
      }
      final tfEvery = _demoMode ? 3 : 6;
      final tfWaiting =
          testFlightBuilds.any((t) => t.state == TestFlightState.processing) ||
              _awaitingTestFlight;
      if (tfWaiting && _ticks % tfEvery == 0) {
        await refreshTestFlight(notify: false);
      }
    } finally {
      _polling = false;
      _updateTicker();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
