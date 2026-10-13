import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../app/theme.dart';
import '../models/build.dart';
import '../models/pipeline.dart';
import '../models/project.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';
import '../widgets/step_line.dart';
import '../widgets/transit_line.dart';

void openBuild(BuildContext context, String buildId) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => BuildDetailScreen(buildId: buildId),
  ));
}

class BuildDetailScreen extends StatefulWidget {
  const BuildDetailScreen({super.key, required this.buildId});

  final String buildId;

  @override
  State<BuildDetailScreen> createState() => _BuildDetailScreenState();
}

class _BuildDetailScreenState extends State<BuildDetailScreen> {
  AppController? _app;
  Timer? _clock;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Keeps elapsed times moving between polls.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _app?.buildById(widget.buildId);
      if (mounted && (current == null || current.isInProgress)) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app == null) {
      final app = AppScope.read(context);
      _app = app;
      app.watch(widget.buildId);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _app?.unwatch(widget.buildId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final current = app.buildById(widget.buildId);

    if (current == null) {
      final error = app.pollError;
      return Scaffold(
        appBar: flatAppBar(context),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: error == null
                ? const CircularProgressIndicator()
                : ErrorNote(message: error),
          ),
        ),
      );
    }

    final snapshot = computePipeline(
      current,
      testFlight: app.testFlightStateFor(current),
      lastSeen: app.lastSeenStation(current.id),
      platform: app.project?.platform ?? AppPlatform.ios,
    );
    final web = app.webUrl(current);
    final message = current.message;

    return Scaffold(
      appBar: flatAppBar(
        context,
        title: Text(current.title),
        actions: [
          if (web != null)
            IconButton(
              tooltip: 'Open in Codemagic',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => openExternal(context, web),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            current.status.label,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: statusColor(current, theme.colorScheme),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _meta(current),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium),
          ],
          if (current.hitPlanLimit) ...[
            const SizedBox(height: 16),
            PlanLimitNotice(detail: current.statusMessage),
          ] else if (!current.isInProgress &&
              current.status != BuildStatus.finished &&
              (current.statusMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            ErrorNote(message: current.statusMessage!),
          ],
          const SizedBox(height: 28),
          TransitLine(snapshot: snapshot),
          const SizedBox(height: 36),
          const SectionTitle('Steps'),
          if (current.steps.isEmpty)
            HintText(current.isInProgress
                ? 'Steps appear once a build machine picks up the job.'
                : 'Codemagic did not return step details for this build. Open it in Codemagic to read the full log.')
          else
            StepLine(
              steps: current.steps,
              logLoader: (step) => app.fetchStepLog(current, step),
            ),
          if (current.artefacts.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionTitle('Artifacts'),
            GroupedPanel(
              children: [
                for (final artefact in current.artefacts)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(artefact.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: artefact.sizeBytes == null
                        ? null
                        : Text(formatBytes(artefact.sizeBytes)),
                    trailing: const Icon(Icons.download_rounded),
                    onTap: () => _download(artefact),
                  ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: SizedBox(
          height: 52,
          child: current.isInProgress
              ? OutlinedButton(
                  onPressed: _busy ? null : () => _cancel(current),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.stop,
                    side: const BorderSide(color: Palette.stop),
                  ),
                  child: Text(_busy ? 'Canceling…' : 'Cancel build'),
                )
              : FilledButton(
                  onPressed: _busy ? null : () => _again(current),
                  child: Text(_busy ? 'Starting…' : 'Build again'),
                ),
        ),
      ),
    );
  }

  String _meta(Build current) {
    final where = [
      if (current.branch != null) 'On ${current.branch}',
      if (current.workflowId != null) 'with ${current.workflowId}',
    ].join(' ');
    final took = formatDuration(current.duration);
    final timing = took.isEmpty
        ? ''
        : current.isInProgress
            ? 'running for $took'
            : 'took $took';
    return [where, timing].where((s) => s.isNotEmpty).join(', ');
  }

  Future<void> _cancel(Build current) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel ${current.title}?'),
        content: const Text('The build machine stops and nothing is uploaded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep building'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.stop),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel build'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await app.cancelBuild(current.id);
      messenger.showSnackBar(SnackBar(content: Text('${current.title} canceled.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _again(Build current) async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final next = await app.startBuild(
        branchOverride: current.branch,
        workflowOverride: current.workflowId,
      );
      messenger.showSnackBar(SnackBar(content: Text('${next.title} started.')));
      navigator.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => BuildDetailScreen(buildId: next.id),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(Artefact artefact) async {
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await app.downloadUrl(artefact);
      if (!mounted) return;
      if (url == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text('This artifact has no download link. Demo builds do not produce real files.'),
        ));
        return;
      }
      await openExternal(context, url);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
