import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../models/pipeline.dart';
import '../models/project.dart';
import '../models/testflight.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';
import '../widgets/transit_line.dart';
import 'pickers.dart';
import '../services/pro_service.dart';
import 'pro_screen.dart';

class TestFlightScreen extends StatefulWidget {
  const TestFlightScreen({super.key});

  @override
  State<TestFlightScreen> createState() => _TestFlightScreenState();
}

class _TestFlightScreenState extends State<TestFlightScreen> {
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    final key = '${app.demoMode}|${app.project?.id}|'
        '${app.project?.bundleId}|${app.store != null}';
    if (key != _loadedFor) {
      _loadedFor = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) app.loadBetaGroups();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final project = app.project;

    final children = <Widget>[
      Text(
        'TestFlight',
        style: theme.textTheme.displaySmall
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      ),
      const SizedBox(height: 4),
      Text(
        project?.bundleId ?? project?.name ?? 'No project',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 24),
    ];

    if (project == null) {
      children.add(const HintText('Add a project first.'));
    } else if (project.platform == AppPlatform.android) {
      children.add(const HintText(
          'This is an Android workflow. Its builds go to Google Play as drafts, '
          'which you roll out from Play Console. Pick an iOS workflow to see '
          'TestFlight here.'));
    } else if (app.store == null) {
      children.add(const HintText(
          'Connect App Store Connect in Settings to see processing status and tester groups.'));
    } else if ((project.bundleId ?? '').isEmpty) {
      children.addAll([
        const HintText(
            'Add your app\'s bundle ID so iBuild can find it in App Store Connect.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _editBundleId(project),
          child: const Text('Add bundle ID'),
        ),
      ]);
    } else {
      children.addAll(_content(app));
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([app.refreshTestFlight(), app.loadBetaGroups()]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: children,
        ),
      ),
    );
  }

  List<Widget> _content(AppController app) {
    final tfError = app.testFlightError;
    final groupsError = app.betaGroupsError;
    return [
      if (tfError != null) ...[
        ErrorNote(message: tfError, onRetry: app.refreshTestFlight),
        const SizedBox(height: 16),
      ],
      const SectionTitle('Builds'),
      if (app.testFlightBuilds.isEmpty)
        HintText(app.loadingTestFlight
            ? 'Checking App Store Connect…'
            : 'No builds have reached App Store Connect yet.')
      else
        GroupedPanel(children: [
          for (final b in app.testFlightBuilds) _TestFlightRow(item: b),
        ]),
      const SizedBox(height: 28),
      const SectionTitle('Tester groups'),
      if (groupsError != null)
        ErrorNote(message: groupsError, onRetry: app.loadBetaGroups)
      else if (app.betaGroups.isEmpty)
        HintText(app.loadingBetaGroups
            ? 'Loading groups…'
            : 'No tester groups yet. Create one in App Store Connect.')
      else
        GroupedPanel(children: [
          for (final g in app.betaGroups) _GroupRow(group: g),
        ]),
    ];
  }

  Future<void> _editBundleId(Project project) async {
    final app = AppScope.read(context);
    final value = await promptForText(
      context,
      title: 'Bundle ID',
      label: 'Bundle ID',
      initial: project.bundleId,
      helper: 'For example com.recipease.app',
    );
    if (value == null || value.isEmpty) return;
    await app.updateProject(project.copyWith(bundleId: value));
  }
}

class _TestFlightRow extends StatelessWidget {
  const _TestFlightRow({required this.item});

  final TestFlightBuild item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = item.expired
        ? StationState.skipped
        : switch (item.state) {
            TestFlightState.ready => StationState.done,
            TestFlightState.processing => StationState.active,
            TestFlightState.failed => StationState.failed,
            _ => StationState.pending,
          };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          StationDot(state: state, size: 16),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  item.stateLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            formatAgo(item.uploadedAt),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatefulWidget {
  const _GroupRow({required this.group});

  final BetaGroup group;

  @override
  State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final link = group.publicLinkEnabled ? group.publicLink : null;

    final String subtitle;
    if (group.isInternal) {
      subtitle = 'Internal group. Testers are added in App Store Connect.';
    } else if (link != null) {
      subtitle = link;
    } else {
      subtitle = 'No public invitation link';
    }

    Widget? trailing;
    if (!group.isInternal) {
      trailing = link != null
          ? IconButton(
              tooltip: 'Copy invitation link',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copy(link),
            )
          : TextButton(
              onPressed: _busy ? null : _createLink,
              child: Text(_busy ? 'Creating…' : 'Create link'),
            );
    }

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: link != null ? () => openExternal(context, Uri.parse(link)) : null,
    );
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Invitation link copied.')));
  }

  Future<void> _createLink() async {
    if (!await requirePro(context, ProFeature.testers) || !mounted) return;
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await app.enablePublicLink(widget.group);
      messenger.showSnackBar(
          const SnackBar(content: Text('Public invitation link created.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
