import 'package:yaml/yaml.dart';

class PubspecInfo {
  const PubspecInfo({this.name, this.version});
  final String? name;
  final String? version;
}

class CodemagicInfo {
  const CodemagicInfo({
    this.workflows = const [],
    this.androidWorkflows = const {},
    this.bundleId,
  });

  /// Workflow keys, which are what the Codemagic API calls `workflowId`.
  final List<String> workflows;

  /// The subset of [workflows] that build Android rather than iOS.
  final Set<String> androidWorkflows;
  final String? bundleId;
}

/// Whether a workflow builds Android: it signs or publishes for Android,
/// builds an App Bundle / APK, or says so in its key.
bool _isAndroidWorkflow(String key, Map workflow) {
  final environment = workflow['environment'];
  final publishing = workflow['publishing'];
  if (environment is Map && environment['android_signing'] != null) return true;
  if (publishing is Map && publishing['google_play'] != null) return true;
  final scripts = workflow['scripts'];
  if (scripts is List &&
      scripts.any((s) =>
          RegExp(r'flutter build (appbundle|apk)').hasMatch(s.toString()))) {
    return true;
  }
  return key.toLowerCase().contains('android');
}

PubspecInfo parsePubspec(String source) {
  try {
    final doc = loadYaml(source);
    if (doc is! Map) return const PubspecInfo();
    return PubspecInfo(
      name: doc['name']?.toString(),
      version: doc['version']?.toString(),
    );
  } on Exception {
    return const PubspecInfo();
  }
}

/// Formats a pubspec version like `2.4.1+87` the way the App Store shows it.
String formatVersion(String? version) {
  if (version == null || version.isEmpty) return 'Unknown';
  final parts = version.split('+');
  return parts.length == 2 ? '${parts[0]} (${parts[1]})' : version;
}

CodemagicInfo parseCodemagicYaml(String source) {
  try {
    final doc = loadYaml(source);
    if (doc is! Map) return const CodemagicInfo();
    final workflows = doc['workflows'];
    if (workflows is! Map) return const CodemagicInfo();
    String? bundleId;
    final android = <String>{};
    for (final entry in workflows.entries) {
      final workflow = entry.value;
      if (workflow is! Map) continue;
      if (_isAndroidWorkflow(entry.key.toString(), workflow)) {
        android.add(entry.key.toString());
      }
      final environment = workflow['environment'];
      if (environment is! Map) continue;
      final signing = environment['ios_signing'];
      if (signing is Map && signing['bundle_identifier'] != null) {
        bundleId ??= signing['bundle_identifier'].toString();
      }
      final vars = environment['vars'];
      if (vars is Map && vars['BUNDLE_ID'] != null) {
        bundleId ??= vars['BUNDLE_ID'].toString();
      }
    }
    return CodemagicInfo(
      workflows: workflows.keys.map((k) => k.toString()).toList(),
      androidWorkflows: android,
      bundleId: bundleId,
    );
  } on Exception {
    return const CodemagicInfo();
  }
}
