/// A buildable app: a Codemagic app plus the workflow and branch to run,
/// optionally linked to its GitHub repository and App Store bundle ID.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.codemagicAppId,
    required this.workflowId,
    required this.branch,
    this.repo,
    this.bundleId,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Untitled',
        codemagicAppId: json['codemagicAppId']?.toString() ?? '',
        workflowId: json['workflowId']?.toString() ?? '',
        branch: json['branch']?.toString() ?? 'main',
        repo: json['repo']?.toString(),
        bundleId: json['bundleId']?.toString(),
      );

  final String id;
  final String name;
  final String codemagicAppId;
  final String workflowId;
  final String branch;

  /// GitHub repository as `owner/name`.
  final String? repo;
  final String? bundleId;

  Project copyWith({String? workflowId, String? bundleId}) => Project(
        id: id,
        name: name,
        codemagicAppId: codemagicAppId,
        workflowId: workflowId ?? this.workflowId,
        branch: branch,
        repo: repo,
        bundleId: bundleId ?? this.bundleId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'codemagicAppId': codemagicAppId,
        'workflowId': workflowId,
        'branch': branch,
        if (repo != null) 'repo': repo,
        if (bundleId != null) 'bundleId': bundleId,
      };
}
