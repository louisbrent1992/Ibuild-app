import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../app/theme.dart';
import '../models/project.dart';
import '../models/repo.dart';
import '../models/pipeline.dart';
import '../services/ci_provider.dart';
import '../widgets/common.dart';
import '../widgets/transit_line.dart';
import 'config_generator_screen.dart';
import 'pickers.dart';

class ProjectSetupScreen extends StatefulWidget {
  const ProjectSetupScreen({super.key, this.existing});

  final Project? existing;

  @override
  State<ProjectSetupScreen> createState() => _ProjectSetupScreenState();
}

class _ProjectSetupScreenState extends State<ProjectSetupScreen> {
  final _name = TextEditingController();
  final _workflow = TextEditingController();
  final _branch = TextEditingController(text: 'main');
  final _bundleId = TextEditingController();
  final _manualAppId = TextEditingController();

  bool _initialized = false;
  Future<List<CiApp>>? _apps;
  String? _appId;
  String? _repo;
  Map<String, GitHubRepo> _repoIndex = {};
  ProjectDetection? _detection;
  bool _detecting = false;
  String? _detectError;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final app = AppScope.read(context);
    final p = widget.existing;
    if (p == null) {
      _apps = app.ci?.listApps();
      return;
    }
    _name.text = p.name;
    _workflow.text = p.workflowId;
    _branch.text = p.branch;
    _bundleId.text = p.bundleId ?? '';
    _appId = p.codemagicAppId;
    _repo = p.repo;
    if (p.repo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _detect();
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _workflow.dispose();
    _branch.dispose();
    _bundleId.dispose();
    _manualAppId.dispose();
    super.dispose();
  }

  bool get _editing => widget.existing != null;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final detection = _detection;
    final canDelete = _editing && !(app.demoMode && widget.existing!.id == 'demo');

    return Scaffold(
      appBar: flatAppBar(
        context,
        title: Text(_editing ? 'Edit project' : 'Add project'),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: 'Delete project',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const SectionTitle('Codemagic app'),
          if (_editing)
            GroupedPanel(children: [PanelRow(label: 'App ID', value: _appId)])
          else
            _appSection(),
          const SizedBox(height: 28),
          const SectionTitle('Repository'),
          _repoSection(app),
          const SizedBox(height: 28),
          const SectionTitle('Build settings'),
          TextField(
            controller: _name,
            decoration: fieldDecoration(context, 'Project name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _workflow,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: fieldDecoration(
              context,
              'Workflow',
              helper: 'The workflow key from codemagic.yaml, for example ios-testflight.',
            ),
          ),
          if (detection != null && detection.workflows.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in detection.workflows)
                  ChoiceChip(
                    label: Text(w),
                    selected: _workflow.text.trim() == w,
                    onSelected: (_) => setState(() => _workflow.text = w),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _branch,
            autocorrect: false,
            decoration: fieldDecoration(context, 'Default branch'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bundleId,
            autocorrect: false,
            decoration: fieldDecoration(
              context,
              'Bundle ID (optional)',
              helper: 'iOS: finds the app in App Store Connect, for example com.recipease.app. Not used for Android workflows.',
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_editing ? 'Save changes' : 'Add project'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appSection() {
    final future = _apps;
    if (future == null) {
      return const HintText(
          'Connect Codemagic in Settings, or turn on demo mode, to choose an app.');
    }
    return FutureBuilder<List<CiApp>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ErrorNote(message: '${snapshot.error}'),
              const SizedBox(height: 12),
              TextField(
                controller: _manualAppId,
                autocorrect: false,
                decoration: fieldDecoration(
                  context,
                  'Codemagic app ID',
                  helper: 'The ID in the app\'s address on codemagic.io.',
                ),
                onChanged: (value) => setState(
                    () => _appId = value.trim().isEmpty ? null : value.trim()),
              ),
            ],
          );
        }
        final apps = snapshot.data ?? const <CiApp>[];
        if (apps.isEmpty) {
          return const HintText(
              'Codemagic has no apps on this account yet. Add your repository in Codemagic first.');
        }
        final primary = Theme.of(context).colorScheme.primary;
        return GroupedPanel(
          children: [
            for (final a in apps)
              ListTile(
                title: Text(a.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(a.id, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: a.id == _appId
                    ? Icon(Icons.check_circle, color: primary)
                    : null,
                onTap: () => setState(() {
                  _appId = a.id;
                  if (_name.text.trim().isEmpty) _name.text = a.name;
                  if (_workflow.text.trim().isEmpty && a.workflows.isNotEmpty) {
                    _workflow.text = a.workflows.keys.first;
                  }
                }),
              ),
          ],
        );
      },
    );
  }

  Widget _repoSection(AppController app) {
    if (app.source == null) {
      return const HintText(
          'Connect GitHub in Settings so iBuild can read versions and codemagic.yaml. You can add the project without it.');
    }
    final detection = _detection;
    final error = _detectError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupedPanel(children: [
          PanelRow(label: 'Repository', value: _repo ?? 'Choose', onTap: _chooseRepo),
        ]),
        if (_detecting)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (error != null) ...[
          const SizedBox(height: 12),
          ErrorNote(message: error, onRetry: _detect),
        ],
        if (detection != null && !_detecting) ...[
          const SizedBox(height: 16),
          GroupedPanel(children: [
            _CheckRow(title: 'Flutter project', file: 'pubspec.yaml', found: detection.hasPubspec),
            _CheckRow(title: 'iOS app', file: 'ios/', found: detection.hasIos),
            _CheckRow(title: 'Android app', file: 'android/', found: detection.hasAndroid),
            _CheckRow(
                title: 'Codemagic configuration',
                file: 'codemagic.yaml',
                found: detection.hasCodemagicYaml),
          ]),
          if (!detection.hasCodemagicYaml) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _openGenerator,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Create codemagic.yaml'),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _chooseRepo() async {
    final source = AppScope.read(context).source;
    if (source == null) return;
    final picked = await showChoiceSheet(
      context,
      title: 'Repository',
      current: _repo,
      manualHint: 'owner/name',
      loader: () async {
        final repos = await source.listRepos();
        _repoIndex = {for (final r in repos) r.fullName: r};
        return repos.map((r) => r.fullName).toList();
      },
    );
    final value = picked?.trim() ?? '';
    if (value.isEmpty || !mounted) return;
    setState(() {
      _repo = value;
      final info = _repoIndex[value];
      if (info != null) _branch.text = info.defaultBranch;
    });
    await _detect();
  }

  Future<void> _detect() async {
    final repo = _repo;
    final source = AppScope.read(context).source;
    if (repo == null || source == null) return;
    final ref = _branch.text.trim();
    setState(() {
      _detecting = true;
      _detectError = null;
    });
    try {
      final result = await source.detect(repo, ref: ref.isEmpty ? null : ref);
      if (!mounted) return;
      setState(() {
        _detection = result;
        if (_workflow.text.trim().isEmpty && result.workflows.isNotEmpty) {
          _workflow.text = result.workflows.firstWhere(
            (w) => w.contains('ios'),
            orElse: () => result.workflows.first,
          );
        }
        final bundle = result.bundleId;
        if (_bundleId.text.trim().isEmpty && bundle != null) {
          _bundleId.text = bundle;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _detectError = e.toString());
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _openGenerator() async {
    final committed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ConfigGeneratorScreen(
          repo: _repo,
          branch: _branch.text.trim(),
          bundleId: _bundleId.text.trim(),
        ),
      ),
    );
    if (committed == true && mounted) await _detect();
  }

  Future<void> _save() async {
    final appId = _appId?.trim() ?? '';
    final name = _name.text.trim();
    final workflow = _workflow.text.trim();
    final branch = _branch.text.trim();
    final bundle = _bundleId.text.trim();
    final missing = [
      if (appId.isEmpty) 'a Codemagic app',
      if (name.isEmpty) 'a project name',
      if (workflow.isEmpty) 'a workflow',
      if (branch.isEmpty) 'a default branch',
    ];
    final messenger = ScaffoldMessenger.of(context);
    if (missing.isNotEmpty) {
      messenger.showSnackBar(
          SnackBar(content: Text('Add ${missing.join(', ')} to continue.')));
      return;
    }
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final project = Project(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      codemagicAppId: appId,
      workflowId: workflow,
      branch: branch,
      repo: _repo,
      bundleId: bundle.isEmpty ? null : bundle,
      // What the repo's codemagic.yaml says beats guessing from the key.
      platform: _detection?.workflows.contains(workflow) == true
          ? (_detection!.androidWorkflows.contains(workflow)
              ? AppPlatform.android
              : AppPlatform.ios)
          : null,
    );
    if (_editing) {
      await app.updateProject(project);
    } else {
      await app.addProject(project);
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${existing.name}?'),
        content: const Text(
            'This removes the project from iBuild. Nothing changes in Codemagic or GitHub.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.stop),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    await app.deleteProject(existing.id);
    navigator.pop();
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.title, required this.file, required this.found});

  final String title;
  final String file;
  final bool found;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          StationDot(
            state: found ? StationState.done : StationState.skipped,
            size: 16,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(
            found ? file : 'missing',
            style: monoStyle(size: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
