import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/build.dart';
import '../models/pipeline.dart';

String formatDuration(Duration? duration) {
  if (duration == null) return '';
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String formatAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 10 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// A short phrase such as "passed in 4m 32s" or "running tests for 12s".
String buildSummary(Build build) {
  final took = formatDuration(build.duration);
  String timed(String phrase, String joiner) =>
      took.isEmpty ? phrase : '$phrase $joiner $took';
  if (build.isInProgress) {
    if (build.status == BuildStatus.queued ||
        build.status == BuildStatus.initializing) {
      return 'waiting for a Mac';
    }
    return timed(build.status.label.toLowerCase(), 'for');
  }
  return switch (build.status) {
    BuildStatus.finished => timed('passed', 'in'),
    BuildStatus.failed => timed('failed', 'after'),
    BuildStatus.timeout => timed('timed out', 'after'),
    BuildStatus.canceled => timed('canceled', 'after'),
    _ => build.status.label.toLowerCase(),
  };
}

Color statusColor(Build build, ColorScheme scheme) {
  if (build.isInProgress) return Palette.amber;
  if (build.status == BuildStatus.finished) return Palette.go;
  if (build.status.isFailure) return Palette.stop;
  return scheme.onSurfaceVariant;
}

StationState dotStateFor(Build build) {
  if (build.isInProgress) return StationState.active;
  if (build.status == BuildStatus.finished) return StationState.done;
  if (build.status.isFailure) return StationState.failed;
  return StationState.skipped;
}
