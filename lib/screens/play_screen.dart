import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../models/pipeline.dart';
import '../models/play.dart';
import '../widgets/common.dart';
import '../widgets/transit_line.dart';

/// The store tab for Android projects: Play releases per track and the
/// Google Groups testing them.
class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final project = app.project;

    final children = <Widget>[
      Text(
        'Google Play',
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
      if (project == null)
        const HintText('Add a project first.')
      else if (app.play == null)
        const HintText(
            'Connect Google Play in Settings to see releases and tester groups.')
      else if ((project.bundleId ?? '').isEmpty)
        const HintText(
            'Add your app\'s package name to the project in Settings so iBuild can find it in Play.')
      else
        ..._content(app),
    ];

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: app.refreshPlay,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: children,
        ),
      ),
    );
  }

  List<Widget> _content(AppController app) {
    final snap = app.playSnapshot;
    final error = app.playError;
    final releases = snap?.releases ?? const <PlayRelease>[];
    final groups = snap?.testerGroups ?? const <String, List<String>>{};
    return [
      if (error != null) ...[
        ErrorNote(message: error, onRetry: app.refreshPlay),
        const SizedBox(height: 16),
      ],
      const SectionTitle('Releases'),
      if (releases.isEmpty)
        HintText(app.loadingPlay
            ? 'Checking Google Play…'
            : 'No releases on any track yet.')
      else
        GroupedPanel(children: [
          for (final r in releases) _ReleaseRow(release: r),
        ]),
      const SizedBox(height: 28),
      const SectionTitle('Tester groups'),
      if (groups.isEmpty)
        HintText(app.loadingPlay
            ? 'Loading groups…'
            : 'No Google Groups on the testing tracks. Email lists are managed in Play Console.')
      else
        GroupedPanel(children: [
          for (final entry in groups.entries)
            for (final group in entry.value)
              ListTile(
                title: Text(group,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(playTrackLabel(entry.key)),
              ),
        ]),
    ];
  }
}

class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({required this.release});

  final PlayRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = switch (release.status) {
      PlayReleaseStatus.completed => StationState.done,
      PlayReleaseStatus.inProgress => StationState.active,
      PlayReleaseStatus.halted => StationState.failed,
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
                Text(release.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${playTrackLabel(release.track)} · ${release.statusLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
