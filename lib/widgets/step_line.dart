import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/build.dart';
import '../models/pipeline.dart';
import 'formatting.dart';
import 'transit_line.dart';

StationState stepState(BuildStep step) {
  if (step.hasFailed) return StationState.failed;
  if (step.isRunning) return StationState.active;
  if (step.wasSkipped) return StationState.skipped;
  if (step.isDone) return StationState.done;
  return StationState.pending;
}

/// Build steps as a vertical line of stations. Tap a step to read its log;
/// logs of running steps refresh as the build moves.
class StepLine extends StatelessWidget {
  const StepLine({super.key, required this.steps, required this.logLoader});

  final List<BuildStep> steps;
  final Future<String?> Function(BuildStep step) logLoader;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            key: ValueKey(steps[i].id.isEmpty ? '$i' : steps[i].id),
            step: steps[i],
            isFirst: i == 0,
            isLast: i == steps.length - 1,
            logLoader: logLoader,
          ),
      ],
    );
  }
}

class _StepRow extends StatefulWidget {
  const _StepRow({
    super.key,
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.logLoader,
  });

  final BuildStep step;
  final bool isFirst;
  final bool isLast;
  final Future<String?> Function(BuildStep step) logLoader;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  static const _dotSize = 17.0;
  static const _dotTop = 3.0;

  bool _open = false;
  Future<String?>? _log;

  void _toggle() {
    setState(() {
      _open = !_open;
      if (_open) _log = widget.logLoader(widget.step);
    });
  }

  @override
  void didUpdateWidget(covariant _StepRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.step.status != widget.step.status;
    if (_open && (widget.step.isRunning || changed)) {
      _log = widget.logLoader(widget.step);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = stepState(widget.step);
    final railColor = state == StationState.done ? scheme.primary : scheme.outline;
    const railCenter = _dotTop + _dotSize / 2;
    final showRail = !(widget.isFirst && widget.isLast);

    return Stack(
      children: [
        if (showRail)
          Positioned(
            left: _dotSize / 2 - 1.5,
            width: 3,
            top: widget.isFirst ? railCenter : 0,
            bottom: widget.isLast ? null : 0,
            height: widget.isLast ? railCenter : null,
            child: ColoredBox(color: railColor),
          ),
        Positioned(
          left: 0,
          top: _dotTop,
          child: StationDot(state: state, size: _dotSize),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 32, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.step.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: state == StationState.failed
                                ? Palette.stop
                                : state == StationState.skipped ||
                                        state == StationState.pending
                                    ? scheme.onSurfaceVariant
                                    : null,
                          ),
                        ),
                      ),
                      Text(
                        formatDuration(widget.step.duration),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _logView(theme),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logView(ThemeData theme) {
    return FutureBuilder<String?>(
      future: _log,
      builder: (context, snapshot) {
        // FutureBuilder keeps the previous data while a refresh is loading,
        // so a live log does not flicker.
        final text = snapshot.data;
        if (text == null) {
          if (snapshot.hasError) {
            return Text('${snapshot.error}',
                style: theme.textTheme.bodySmall?.copyWith(color: Palette.stop));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator(minHeight: 2);
          }
          return Text(
            'No log is available for this step.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }
        return Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: Palette.terminal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            reverse: widget.step.isRunning,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text.trimRight().isEmpty ? '(empty)' : text.trimRight(),
              style: monoStyle(size: 11.5, color: Palette.terminalText),
            ),
          ),
        );
      },
    );
  }
}
