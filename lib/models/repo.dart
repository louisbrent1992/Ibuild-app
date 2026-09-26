class GitHubRepo {
  const GitHubRepo({
    required this.fullName,
    required this.defaultBranch,
    this.isPrivate = false,
    this.description,
  });

  final String fullName;
  final String defaultBranch;
  final bool isPrivate;
  final String? description;
}

/// What iBuild found when it looked inside a repository.
class ProjectDetection {
  const ProjectDetection({
    this.hasPubspec = false,
    this.hasIos = false,
    this.hasAndroid = false,
    this.hasCodemagicYaml = false,
    this.appName,
    this.version,
    this.workflows = const [],
    this.bundleId,
  });

  final bool hasPubspec;
  final bool hasIos;
  final bool hasAndroid;
  final bool hasCodemagicYaml;
  final String? appName;
  final String? version;
  final List<String> workflows;
  final String? bundleId;

  bool get isFlutter => hasPubspec;
}
