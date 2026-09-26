import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/services/yaml_parsing.dart';

void main() {
  test('parsePubspec reads name and version', () {
    final info = parsePubspec('name: recipease\nversion: 2.4.1+87\n');
    expect(info.name, 'recipease');
    expect(info.version, '2.4.1+87');
  });

  test('parsePubspec tolerates broken YAML', () {
    final info = parsePubspec('name: [unclosed');
    expect(info.name, isNull);
    expect(info.version, isNull);
  });

  test('formatVersion matches the App Store style', () {
    expect(formatVersion('2.4.1+87'), '2.4.1 (87)');
    expect(formatVersion('1.0.0'), '1.0.0');
    expect(formatVersion(null), 'Unknown');
  });

  test('parseCodemagicYaml finds workflow keys and bundle ID', () {
    const source = '''
workflows:
  ios-release:
    environment:
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.example.one
  android-release:
    environment:
      flutter: stable
''';
    final info = parseCodemagicYaml(source);
    expect(info.workflows, ['ios-release', 'android-release']);
    expect(info.bundleId, 'com.example.one');
  });
}
