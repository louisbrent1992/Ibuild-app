import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../services/config_generator.dart';
import '../widgets/common.dart';

/// Builds a codemagic.yaml from a few choices and commits it to the repo.
class ConfigGeneratorScreen extends StatefulWidget {
  const ConfigGeneratorScreen({super.key, this.repo, this.branch, this.bundleId});

  final String? repo;
  final String? branch;
  final String? bundleId;

  @override
  State<ConfigGeneratorScreen> createState() => _ConfigGeneratorScreenState();
}

class _ConfigGeneratorScreenState extends State<ConfigGeneratorScreen> {
  var _options = const ConfigOptions(android: true);
  late final _bundle = TextEditingController(
    text: (widget.bundleId ?? '').isNotEmpty ? widget.bundleId : 'com.example.app',
  );
  final _integration = TextEditingController(text: 'iBuild');
  final _group = TextEditingController(text: 'App testers');
  bool _committing = false;

  @override
  void dispose() {
    _bundle.dispose();
    _integration.dispose();
    _group.dispose();
    super.dispose();
  }

  ConfigOptions get _current {
    final bundle = _bundle.text.trim();
    return _options.copyWith(
      bundleId: bundle.isEmpty ? 'com.example.app' : bundle,
      integrationName: _integration.text.trim(),
      betaGroup: _group.text.trim(),
    );
  }

  void _set(ConfigOptions options) => setState(() => _options = options);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final options = _current;
    final nothing = !options.ios && !options.android;
    final yaml = nothing ? '' : generateCodemagicYaml(options);
    final repo = widget.repo;
    final canCommit = repo != null && app.source != null && !nothing;

    return Scaffold(
      appBar: flatAppBar(context, title: const Text('codemagic.yaml')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const SectionTitle('Platforms'),
          GroupedPanel(
            children: [
              CheckboxListTile(
                value: _options.ios,
                title: const Text('iOS'),
                onChanged: (v) => _set(_options.copyWith(ios: v ?? false)),
              ),
              CheckboxListTile(
                value: _options.android,
                title: const Text('Android'),
                onChanged: (v) => _set(_options.copyWith(android: v ?? false)),
              ),
            ],
          ),
          if (_options.ios) ...[
            const SizedBox(height: 24),
            const SectionTitle('iOS distribution'),
            SegmentedButton<Distribution>(
              showSelectedIcon: false,
              segments: [
                for (final d in Distribution.values)
                  ButtonSegment(value: d, label: Text(d.label)),
              ],
              selected: {_options.distribution},
              onSelectionChanged: (selection) =>
                  _set(_options.copyWith(distribution: selection.first)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bundle,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: fieldDecoration(context, 'Bundle ID'),
            ),
            if (_options.distribution != Distribution.adHoc) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _integration,
                onChanged: (_) => setState(() {}),
                decoration: fieldDecoration(
                  context,
                  'App Store Connect integration',
                  helper: 'The name of the API key integration in your Codemagic team settings.',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _group,
                onChanged: (_) => setState(() {}),
                decoration: fieldDecoration(
                  context,
                  'TestFlight group',
                  helper: 'Testers in this group get every new build.',
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          GroupedPanel(
            children: [
              SwitchListTile(
                value: _options.runTests,
                title: const Text('Run flutter test before building'),
                onChanged: (v) => _set(_options.copyWith(runTests: v)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionTitle('Preview'),
          if (nothing)
            const HintText('Choose at least one platform.')
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.terminal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  yaml,
                  style: monoStyle(size: 11.5, color: Palette.terminalText),
                ),
              ),
            ),
          if (!canCommit && !nothing) ...[
            const SizedBox(height: 12),
            const HintText(
                'Copy this into the root of your repository, or link a GitHub repository to the project to commit it from here.'),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: nothing ? null : () => _copy(yaml),
                  child: const Text('Copy'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: repo != null && canCommit && !_committing
                      ? () => _commit(repo, yaml)
                      : null,
                  child: Text(_committing ? 'Committing…' : 'Commit to repo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(String yaml) async {
    await Clipboard.setData(ClipboardData(text: yaml));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('codemagic.yaml copied.')));
  }

  Future<void> _commit(String repo, String yaml) async {
    final source = AppScope.read(context).source;
    if (source == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final branch = (widget.branch ?? '').isNotEmpty ? widget.branch : null;
    setState(() => _committing = true);
    try {
      await source.writeFile(
        repo,
        'codemagic.yaml',
        yaml,
        message: 'Add codemagic.yaml from iBuild',
        branch: branch,
      );
      messenger.showSnackBar(SnackBar(
        content: Text('Committed codemagic.yaml to ${branch ?? 'the default branch'}.'),
      ));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }
}
