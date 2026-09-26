import '../models/build.dart';

class CiApp {
  const CiApp({
    required this.id,
    required this.name,
    this.branches = const [],
    this.workflows = const {},
  });

  final String id;
  final String name;
  final List<String> branches;

  /// Workflow Editor workflows by ID. Apps configured with codemagic.yaml
  /// return none here; their workflow keys are read from the repository.
  final Map<String, String> workflows;
}

/// Anything that can run a build on a Mac somewhere else. Codemagic is the
/// first implementation; GitHub Actions, Bitrise or Xcode Cloud can follow.
abstract class CiProvider {
  String get name;
  Future<List<CiApp>> listApps();
  Future<String> startBuild({
    required String appId,
    required String workflowId,
    required String branch,
  });
  Future<Build> getBuild(String buildId);
  Future<List<Build>> listBuilds({required String appId});
  Future<void> cancelBuild(String buildId);
  Future<String?> fetchStepLog(Build build, BuildStep step);
  Future<Uri?> downloadUrl(Artefact artefact);
  Uri? webUrl(Build build);
}
