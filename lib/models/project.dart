/// Which store a workflow ships to. One Codemagic workflow builds one
/// platform, so a project (app + workflow) has exactly one.
enum AppPlatform {
  ios('iOS'),
  android('Android');

  const AppPlatform(this.label);
  final String label;
}

/// Best guess from the workflow key alone, for projects saved before the
/// platform was stored and for workflows typed by hand.
AppPlatform platformForWorkflow(String workflowId) =>
    workflowId.toLowerCase().contains('android')
        ? AppPlatform.android
        : AppPlatform.ios;

/// A buildable app: a Codemagic app plus the workflow and branch to run,
/// optionally linked to its GitHub repository and bundle ID / package name.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.codemagicAppId,
    required this.workflowId,
    required this.branch,
    this.repo,
    this.bundleId,
    AppPlatform? platform,
  }) : _platform = platform;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Untitled',
        codemagicAppId: json['codemagicAppId']?.toString() ?? '',
        workflowId: json['workflowId']?.toString() ?? '',
        branch: json['branch']?.toString() ?? 'main',
        repo: json['repo']?.toString(),
        bundleId: json['bundleId']?.toString(),
        platform: AppPlatform.values
            .where((p) => p.name == json['platform'])
            .firstOrNull,
      );

  final String id;
  final String name;
  final String codemagicAppId;
  final String workflowId;
  final String branch;

  /// GitHub repository as `owner/name`.
  final String? repo;
  final String? bundleId;
  final AppPlatform? _platform;

  AppPlatform get platform => _platform ?? platformForWorkflow(workflowId);

  Project copyWith({String? workflowId, String? bundleId, AppPlatform? platform}) =>
      Project(
        id: id,
        name: name,
        codemagicAppId: codemagicAppId,
        workflowId: workflowId ?? this.workflowId,
        branch: branch,
        repo: repo,
        bundleId: bundleId ?? this.bundleId,
        platform: platform ?? _platform,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'codemagicAppId': codemagicAppId,
        'workflowId': workflowId,
        'branch': branch,
        if (repo != null) 'repo': repo,
        if (bundleId != null) 'bundleId': bundleId,
        'platform': platform.name,
      };
}
