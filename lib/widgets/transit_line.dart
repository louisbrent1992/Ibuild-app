import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/pipeline.dart';

/// The build pipeline drawn as a transit line: each stage is a station, the
/// travelled part of the line is solid colour, and the station the build is
/// at right now pulses amber.
class TransitLine extends StatelessWidget {
  const TransitLine({super.key, required this.snapshot});

  final PipelineSnapshot snapshot;

  static String _describe(StationState state) => switch (state) {
        StationState.pending => 'not started',
        StationState.active => 'in progress',
        StationState.done => 'done',
        StationState.failed => 'failed',
        StationState.skipped => 'skipped',
      };

  @override
  Widget build(BuildContext context) {
    final stations = Station.values;
    final description = [
      for (final s in stations)
        '${s.labelFor(snapshot.platform)} ${_describe(snapshot[s])}',
    ].join(', ');
    return Semantics(
      container: true,
      label: snapshot.waiting
          ? 'Waiting for a build machine. $description'
          : 'Pipeline: $description',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < stations.length; i++)
              Expanded(
                child: _StationColumn(
                  station: stations[i],
                  label: stations[i].labelFor(snapshot.platform),
                  state: snapshot[stations[i]],
                  previousDone:
                      i > 0 && snapshot[stations[i - 1]] == StationState.done,
                  isFirst: i == 0,
                  isLast: i == stations.length - 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StationColumn extends StatelessWidget {
  const _StationColumn({
    required this.station,
    required this.label,
    required this.state,
    required this.previousDone,
    required this.isFirst,
    required this.isLast,
  });

  final Station station;
  final String label;
  final StationState state;
  final bool previousDone;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final travelled = scheme.primary;
    final rail = scheme.outline;
    final left = isFirst
        ? Colors.transparent
        : previousDone
            ? travelled
            : rail;
    final right = isLast
        ? Colors.transparent
        : state == StationState.done
            ? travelled
            : rail;
    final labelColor = switch (state) {
      StationState.failed => Palette.stop,
      StationState.pending || StationState.skipped => scheme.onSurfaceVariant,
      _ => scheme.onSurface,
    };
    return Column(
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: [
              Expanded(child: Container(height: 5, color: left)),
              StationDot(state: state, size: 20),
              Expanded(child: Container(height: 5, color: right)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelMedium?.copyWith(
              color: labelColor,
              fontWeight: state == StationState.active
                  ? FontWeight.w800
                  : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// A single station marker. Only the active station animates, and only when
/// the system allows animations.
class StationDot extends StatefulWidget {
  const StationDot({super.key, required this.state, this.size = 18});

  final StationState state;
  final double size;

  @override
  State<StationDot> createState() => _StationDotState();
}

class _StationDotState extends State<StationDot> with TickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant StationDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    final shouldPulse = widget.state == StationState.active;
    if (shouldPulse && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..repeat();
    } else if (!shouldPulse && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final marker = _marker(Theme.of(context).colorScheme, size);
    final pulse = _pulse;
    if (pulse == null || MediaQuery.disableAnimationsOf(context)) {
      return SizedBox.square(dimension: size, child: marker);
    }
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              final t = Curves.easeOut.transform(pulse.value);
              return Transform.scale(
                scale: 1 + 0.9 * t,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Palette.amber.withValues(alpha: 0.4 * (1 - t)),
                  ),
                ),
              );
            },
          ),
          marker,
        ],
      ),
    );
  }

  Widget _marker(ColorScheme scheme, double size) {
    Widget circle({
      required Color fill,
      Color? border,
      double borderWidth = 0,
      Widget? child,
    }) =>
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: border == null
                ? null
                : Border.all(color: border, width: borderWidth),
          ),
          child: child,
        );

    return switch (widget.state) {
      StationState.done => circle(
          fill: scheme.primary,
          child: Icon(Icons.check_rounded, size: size * 0.7, color: scheme.onPrimary),
        ),
      StationState.active =>
        circle(fill: scheme.surface, border: Palette.amber, borderWidth: size * 0.25),
      StationState.failed => circle(
          fill: Palette.stop,
          child: Icon(Icons.close_rounded, size: size * 0.7, color: Colors.white),
        ),
      StationState.skipped => circle(
          fill: scheme.surface,
          border: scheme.outline,
          borderWidth: 2,
          child: Container(width: size * 0.4, height: 2, color: scheme.outline),
        ),
      StationState.pending =>
        circle(fill: scheme.surface, border: scheme.outline, borderWidth: size * 0.17),
    };
  }
}
