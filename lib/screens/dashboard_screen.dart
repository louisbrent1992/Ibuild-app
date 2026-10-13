import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../app/theme.dart';
import '../models/build.dart';
import '../models/pipeline.dart';
import '../models/project.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';
import '../widgets/transit_line.dart';
import 'build_detail_screen.dart';
import 'pickers.dart';
import 'project_setup_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenTestFlight,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenTestFlight;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final project = app.project;
    if (project == null) {
      return SafeArea(child: _NoProject(onOpenSettings: onOpenSettings));
    }

    final latest = app.latestBuild;
    final lastFinished = app.builds.where((b) => !b.isInProgress).firstOrNull;
    final snapshot = computePipeline(
      latest,
      testFlight: app.testFlightStateFor(latest),
      lastSeen: latest == null ? null : app.lastSeenStation(latest.id),
      platform: project.platform,
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: app.refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _ProjectHeader(project: project, demo: app.demoMode),
            const SizedBox(height: 6),
            _StatusLine(latest: latest),
            const SizedBox(height: 36),
            _LineCaption(latest: latest),
            const SizedBox(height: 14),
            TransitLine(snapshot: snapshot),
            if (app.buildsError != null) ...[
              const SizedBox(height: 16),
              ErrorNote(message: app.buildsError!, onRetry: app.refreshBuilds),
            ],
            const SizedBox(height: 36),
            GroupedPanel(
              children: [
                PanelRow(
                  label: 'Branch',
                  value: app.branch,
                  onTap: () => showBranchPicker(context),
                ),
                PanelRow(
                  label: 'Workflow',
                  value: project.workflowId,
                  onTap: () => showWorkflowPicker(context),
                ),
                PanelRow(label: 'Version', value: _versionText(app, project)),
              ],
            ),
            const SizedBox(height: 20),
            _BuildButton(latest: latest),
            if (app.ci == null) ...[
              const SizedBox(height: 10),
              Text(
                'Connect Codemagic in Settings to start builds.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 32),
            GroupedPanel(
              children: [
                PanelRow(
                  label: 'Last build',
                  value: lastFinished == null
                      ? 'None yet'
                      : '${lastFinished.title}, ${buildSummary(lastFinished)}',
                  onTap: lastFinished == null
                      ? null
                      : () => openBuild(context, lastFinished.id),
                ),
                PanelRow(
                  label: 'TestFlight',
                  value: _testFlightText(app),
                  onTap: onOpenTestFlight,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _versionText(AppController app, Project project) {
    if (project.repo == null) return 'Link a repository';
    if (app.source == null) return 'Connect GitHub';
    if (app.loadingVersion && app.versionLabel == null) return 'Checking…';
    return app.versionLabel ?? 'No pubspec.yaml';
  }

  static String _testFlightText(AppController app) {
    if (app.store == null) return 'Connect App Store Connect';
    if ((app.project?.bundleId ?? '').isEmpty) return 'Add a bundle ID';
    if (app.testFlightError != null) return 'Could not load';
    final newest = app.testFlightBuilds.firstOrNull;
    if (newest == null) {
      return app.loadingTestFlight ? 'Checking…' : 'No builds yet';
    }
    return '${newest.label}, ${newest.stateLabel.toLowerCase()}';
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.project, required this.demo});

  final Project project;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => showProjectSheet(context),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more,
                    size: 28, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (demo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Palette.amber.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Demo',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: dark ? Palette.amber : const Color(0xFF8A5A00),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.latest});

  final Build? latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = latest;
    final running = current != null && current.isInProgress;
    final text = (current != null && current.isInProgress)
        ? '${current.title}: ${current.status.label.toLowerCase()}'
        : 'Ready to build';
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: running ? Palette.amber : Palette.go,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _LineCaption extends StatelessWidget {
  const _LineCaption({required this.latest});

  final Build? latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = latest;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    if (current == null) return Text('No builds yet', style: style);
    return Row(
      children: [
        Expanded(
          child: Text(
            '${current.title} on ${current.branch ?? 'unknown branch'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        Text(formatDuration(current.duration), style: style),
      ],
    );
  }
}

class _BuildButton extends StatelessWidget {
  const _BuildButton({required this.latest});

  final Build? latest;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final current = latest;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final textStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);

    if (current != null && current.isInProgress) {
      return SizedBox(
        height: 58,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: shape,
            textStyle: textStyle,
            side: const BorderSide(color: Palette.amber, width: 2),
          ),
          onPressed: () => openBuild(context, current.id),
          child: Text('Watch ${current.title}'),
        ),
      );
    }

    final enabled = app.ci != null && !app.starting;
    return SizedBox(
      height: 58,
      child: FilledButton(
        style: FilledButton.styleFrom(shape: shape, textStyle: textStyle),
        onPressed: enabled ? () => _start(context) : null,
        child: app.starting
            ? SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : const Text('Build & test'),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final started = await app.startBuild();
      messenger.showSnackBar(SnackBar(
        content: Text('${started.title} started on ${started.branch ?? app.branch}.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _NoProject extends StatelessWidget {
  const _NoProject({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add your first project',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              app.ci == null
                  ? 'Add a Codemagic API token in Settings, or turn on demo mode to look around first.'
                  : 'Pick a Codemagic app and, if you like, its GitHub repository.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            if (app.ci == null)
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('Open Settings'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProjectSetupScreen(),
                  ),
                ),
                child: const Text('Add project'),
              ),
          ],
        ),
      ),
    );
  }
}
