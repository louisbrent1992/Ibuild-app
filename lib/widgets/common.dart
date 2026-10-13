import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';

/// A white card holding rows separated by hairlines.
class GroupedPanel extends StatelessWidget {
  const GroupedPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, indent: 16, color: scheme.outline),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A label on the left and a value on the right, like a settings row.
class PanelRow extends StatelessWidget {
  const PanelRow({super.key, required this.label, this.value, this.onTap});

  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value ?? '',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Quiet explanatory text used where a section has nothing to show yet.
class HintText extends StatelessWidget {
  const HintText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
      ),
    );
  }
}

class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Palette.stop.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.stop.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: Palette.stop, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

AppBar flatAppBar(BuildContext context, {Widget? title, List<Widget>? actions}) {
  final theme = Theme.of(context);
  return AppBar(
    title: title,
    actions: actions,
    backgroundColor: theme.scaffoldBackgroundColor,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    titleTextStyle:
        theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
  );
}

Future<void> openExternal(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open ${uri.host}.')));
  }
}

final codemagicPlansUrl = Uri.parse('https://codemagic.io/pricing/');

/// Shown when Codemagic stopped or refused a build over the account's plan,
/// so it is clear the limit is Codemagic's, not iBuild's or the code's.
class PlanLimitNotice extends StatelessWidget {
  const PlanLimitNotice({super.key, this.detail});

  /// Codemagic's own wording, shown under the explanation.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Palette.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.hourglass_bottom, color: Palette.amber, size: 20),
            const SizedBox(width: 10),
            Text('Codemagic plan limit',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Codemagic stopped this build because of your Codemagic plan, not because '
            'of iBuild or your code. You may have used this month\'s build minutes, or '
            'the workflow needs a machine your plan does not include. Builds run again '
            'when your minutes reset or after you change plan in Codemagic.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Codemagic says: $detail',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          TextButton(
            onPressed: () => openExternal(context, codemagicPlansUrl),
            child: const Text('Codemagic plans'),
          ),
        ],
      ),
    );
  }
}
