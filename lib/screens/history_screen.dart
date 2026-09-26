import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../models/build.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';
import '../widgets/transit_line.dart';
import 'build_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final builds = app.builds;
    final error = app.buildsError;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: app.refreshBuilds,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'History',
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
            const SizedBox(height: 4),
            Text(
              app.project?.name ?? 'No project',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            if (error != null) ...[
              ErrorNote(message: error, onRetry: app.refreshBuilds),
              const SizedBox(height: 16),
            ],
            if (builds.isEmpty)
              HintText(app.loadingBuilds
                  ? 'Loading builds…'
                  : 'No builds yet. Start one from the Build tab.')
            else
              GroupedPanel(
                children: [for (final b in builds) _HistoryRow(entry: b)],
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final Build entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => openBuild(context, entry.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            StationDot(state: dotStateFor(entry), size: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.branch ?? 'unknown branch'}, ${buildSummary(entry)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatAgo(entry.createdAt ?? entry.startedAt),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
