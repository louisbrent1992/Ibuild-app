import 'package:yaml/yaml.dart';

class PubspecInfo {
  const PubspecInfo({this.name, this.version});
  final String? name;
  final String? version;
}

class CodemagicInfo {
  const CodemagicInfo({this.workflows = const [], this.bundleId});

  /// Workflow keys, which are what the Codemagic API calls `workflowId`.
  final List<String> workflows;
  final String? bundleId;
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
    for (final workflow in workflows.values) {
      if (workflow is! Map) continue;
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
      bundleId: bundleId,
    );
  } on Exception {
    return const CodemagicInfo();
  }
}
