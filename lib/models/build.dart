import 'dart:math' as math;

/// Build states reported by Codemagic.
enum BuildStatus {
  initializing,
  queued,
  preparing,
  fetching,
  testing,
  building,
  publishing,
  finishing,
  finished,
  failed,
  canceled,
  timeout,
  skipped,
  unknown;

  static BuildStatus parse(Object? raw) {
    final value = raw?.toString().toLowerCase().trim() ?? '';
    for (final status in BuildStatus.values) {
      if (status.name == value) return status;
    }
    return switch (value) {
      'cancelled' => BuildStatus.canceled,
      'success' || 'succeeded' || 'passed' => BuildStatus.finished,
      'error' || 'errored' => BuildStatus.failed,
      _ => BuildStatus.unknown,
    };
  }

  /// True for every status Codemagic uses while a build is still running.
  bool get isInProgress => index <= BuildStatus.finishing.index;

  bool get isFailure =>
      this == BuildStatus.failed || this == BuildStatus.timeout;

  String get label => switch (this) {
        BuildStatus.initializing || BuildStatus.queued => 'Waiting for a Mac',
        BuildStatus.preparing => 'Preparing machine',
        BuildStatus.fetching => 'Fetching sources',
        BuildStatus.testing => 'Running tests',
        BuildStatus.building => 'Building',
        BuildStatus.publishing => 'Uploading',
        BuildStatus.finishing => 'Finishing up',
        BuildStatus.finished => 'Passed',
        BuildStatus.failed => 'Failed',
        BuildStatus.canceled => 'Canceled',
        BuildStatus.timeout => 'Timed out',
        BuildStatus.skipped => 'Skipped',
        BuildStatus.unknown => 'Status unknown',
      };
}

// Codemagic's API is in preview and has shipped more than one response shape,
// so parsing looks for each field under every name it has been seen with.

String? _string(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    if (value is num) return value.toString();
  }
  return null;
}

int? _int(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

DateTime? _date(Map<String, dynamic> json, List<String> keys) {
  final raw = _string(json, keys);
  return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

/// One step of a build, such as "Flutter tests" or "Publishing".
class BuildStep {
  const BuildStep({
    required this.id,
    required this.name,
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.logUrl,
    this.inlineLog,
  });

  factory BuildStep.fromJson(Map<String, dynamic> json) => BuildStep(
        id: _string(json, ['_id', 'id']) ?? '',
        name: _string(json, ['name', 'title']) ?? 'Step',
        status: (_string(json, ['status', 'state']) ?? '').toLowerCase(),
        startedAt: _date(json, ['startedAt', 'started_at']),
        finishedAt: _date(json, ['finishedAt', 'finished_at']),
        logUrl: _string(json, ['logUrl', 'log_url', 'logsUrl']),
      );

  final String id;
  final String name;
  final String status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? logUrl;

  /// Log text supplied directly, used by demo mode.
  final String? inlineLog;

  bool get hasFailed => const {'failed', 'error', 'timeout'}.contains(status);

  bool get wasSkipped =>
      const {'skipped', 'canceled', 'cancelled'}.contains(status);

  bool get isRunning =>
      const {'running', 'in_progress', 'building', 'started'}
          .contains(status) ||
      (status.isEmpty && startedAt != null && finishedAt == null);

  bool get isDone =>
      const {'success', 'finished', 'completed', 'passed'}.contains(status) ||
      (!hasFailed && !wasSkipped && finishedAt != null);

  Duration? get duration {
    final start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }
}

/// A file a build produced, such as an .ipa or .aab.
class Artefact {
  const Artefact({
    required this.name,
    required this.url,
    this.type,
    this.sizeBytes,
  });

  factory Artefact.fromJson(Map<String, dynamic> json) => Artefact(
        name: _string(json, ['name']) ?? 'artifact',
        url: _string(json, ['url', 'downloadUrl']) ?? '',
        type: _string(json, ['type']),
        sizeBytes: _int(json, ['size']),
      );

  final String name;
  final String url;
  final String? type;
  final int? sizeBytes;
}

class Build {
  const Build({
    required this.id,
    required this.appId,
    required this.status,
    this.workflowId,
    this.branch,
    this.number,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.steps = const [],
    this.artefacts = const [],
    this.message,
    this.statusMessage,
  });

  /// What we know about a build the moment Codemagic accepts it.
  factory Build.placeholder({
    required String id,
    required String appId,
    required String workflowId,
    required String branch,
  }) =>
      Build(
        id: id,
        appId: appId,
        status: BuildStatus.queued,
        workflowId: workflowId,
        branch: branch,
        createdAt: DateTime.now(),
      );

  /// Reads the legacy `{build: {...}}` shape, the v3 `{data: {...}}` shape,
  /// and bare build objects from list endpoints.
  factory Build.fromCodemagic(Map<String, dynamic> raw) {
    final json = raw['build'] is Map
        ? _map(raw['build'])
        : raw['data'] is Map
            ? _map(raw['data'])
            : raw;
    final app = json['app'] ?? json['application'] ?? raw['application'];
    final appId = _string(json, ['appId', 'app_id', 'applicationId']) ??
        (app is String ? app : _string(_map(app), ['_id', 'id'])) ??
        '';
    final commit = _map(json['commit']);
    return Build(
      id: _string(json, ['_id', 'id', 'buildId']) ?? '',
      appId: appId,
      status: BuildStatus.parse(json['status']),
      workflowId:
          _string(json, ['fileWorkflowId', 'workflowId', 'workflow_id']) ??
              _string(_map(json['workflow']), ['id', 'name']),
      branch: _string(json, ['branch']) ?? _string(commit, ['branch']),
      number: _int(json, ['index', 'buildNumber', 'number']),
      createdAt: _date(json, ['createdAt', 'created_at']),
      startedAt: _date(json, ['startedAt', 'started_at']),
      finishedAt: _date(json, ['finishedAt', 'finished_at']),
      steps: _maps(json['buildActions'] ?? json['steps'] ?? json['actions'])
          .map(BuildStep.fromJson)
          .toList(),
      artefacts: _maps(json['artefacts'] ?? json['artifacts'])
          .map(Artefact.fromJson)
          .where((a) => a.url.isNotEmpty)
          .toList(),
      message: _string(commit, ['commitMessage', 'message']),
      // Codemagic's own reason, e.g. "The selected instance type is not
      // available with the current billing plan."
      statusMessage: _string(json, ['message', 'statusMessage', 'failureReason']),
    );
  }

  final String id;
  final String appId;
  final BuildStatus status;
  final String? workflowId;
  final String? branch;
  final int? number;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<BuildStep> steps;
  final List<Artefact> artefacts;

  /// The commit message.
  final String? message;

  /// Why Codemagic stopped or refused the build, when it says.
  final String? statusMessage;

  /// True when Codemagic stopped the build over the account's plan (build
  /// minutes, billing, a machine the plan does not include) rather than
  /// anything in the code or in iBuild.
  bool get hitPlanLimit => isCodemagicPlanLimit(statusMessage);

  bool get isInProgress =>
      status.isInProgress ||
      (status == BuildStatus.unknown && finishedAt == null);

  Duration? get duration {
    final start = startedAt ?? createdAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  String get title => number != null
      ? 'Build #$number'
      : 'Build ${id.substring(0, math.min(6, id.length))}';

  /// Lays a fresher copy over this one, keeping anything the fresh copy lacks.
  Build mergedWith(Build fresh) => Build(
        id: id,
        appId: fresh.appId.isNotEmpty ? fresh.appId : appId,
        status: fresh.status,
        workflowId: fresh.workflowId ?? workflowId,
        branch: fresh.branch ?? branch,
        number: fresh.number ?? number,
        createdAt: fresh.createdAt ?? createdAt,
        startedAt: fresh.startedAt ?? startedAt,
        finishedAt: fresh.finishedAt ?? finishedAt,
        steps: fresh.steps.isNotEmpty ? fresh.steps : steps,
        artefacts: fresh.artefacts.isNotEmpty ? fresh.artefacts : artefacts,
        message: fresh.message ?? message,
        statusMessage: fresh.statusMessage ?? statusMessage,
      );
}

final _planLimit = RegExp(
  r'billing|build minutes|out of minutes|minutes? (limit|quota)|quota|'
  r'limit (reached|exceeded)|payment|upgrade your (plan|account)|'
  r'(current|your) plan|free plan|trial (has )?(ended|expired)',
  caseSensitive: false,
);

/// Whether a Codemagic message is about the account's plan or minutes.
bool isCodemagicPlanLimit(String? text) =>
    text != null && _planLimit.hasMatch(text);
