import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/services/config_generator.dart';
import 'package:ibuild/services/yaml_parsing.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('TestFlight config is valid YAML with both workflows', () {
    final text = generateCodemagicYaml(const ConfigOptions(
      ios: true,
      android: true,
      bundleId: 'com.recipease.app',
    ));
    final doc = loadYaml(text) as YamlMap;
    final workflows = doc['workflows'] as YamlMap;
    expect(workflows.keys, containsAll(['ios-testflight', 'android-release']));

    final ios = workflows['ios-testflight'] as YamlMap;
    expect(ios['environment']['ios_signing']['bundle_identifier'],
        'com.recipease.app');
    expect(ios['publishing']['app_store_connect']['submit_to_testflight'], isTrue);
    expect(ios['publishing']['app_store_connect']['beta_groups'],
        contains('App testers'));
    final scripts = (ios['scripts'] as YamlList).map((s) => s['name']).toList();
    expect(scripts, contains('Flutter tests'));
  });

  test('App Store config also submits for review', () {
    final text = generateCodemagicYaml(
        const ConfigOptions(distribution: Distribution.appStore));
    final doc = loadYaml(text) as YamlMap;
    final ios = doc['workflows']['ios-app-store'] as YamlMap;
    expect(ios['publishing']['app_store_connect']['submit_to_app_store'], isTrue);
  });

  test('Ad Hoc config skips App Store Connect publishing', () {
    final text = generateCodemagicYaml(
        const ConfigOptions(distribution: Distribution.adHoc));
    final doc = loadYaml(text) as YamlMap;
    final ios = doc['workflows']['ios-ad-hoc'] as YamlMap;
    expect(ios['environment']['ios_signing']['distribution_type'], 'ad_hoc');
    expect(ios.containsKey('publishing'), isFalse);
    expect(ios.containsKey('integrations'), isFalse);
  });

  test('turning tests off removes the test step', () {
    final text = generateCodemagicYaml(const ConfigOptions(runTests: false));
    expect(text.contains('flutter test'), isFalse);
  });

  test('generated config reads back through parseCodemagicYaml', () {
    final info = parseCodemagicYaml(generateCodemagicYaml(const ConfigOptions(
      android: true,
      bundleId: 'com.recipease.app',
    )));
    expect(info.workflows, ['ios-testflight', 'android-release']);
    expect(info.bundleId, 'com.recipease.app');
  });
}
