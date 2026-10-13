import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../services/pro_service.dart';
import '../widgets/common.dart';
import 'account_screen.dart';

final eulaUrl = Uri.parse('https://adventhubsolutions.com/apps/ibuild/eula');

/// Opens the paywall when [feature] needs Pro. Returns whether the user has
/// Pro afterwards. Demo mode is a free trial of everything, so it never asks.
Future<bool> requirePro(BuildContext context, ProFeature feature) async {
  final app = AppScope.read(context);
  if (app.isPro || app.demoMode) return true;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ProScreen(reason: feature),
  ));
  return app.isPro;
}

class ProScreen extends StatefulWidget {
  const ProScreen({super.key, this.reason});

  /// The feature that brought the user here, listed first.
  final ProFeature? reason;

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  String? _price;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).pro.price().then((p) {
      if (mounted) setState(() => _price = p);
    });
  }

  Future<void> _run(Future<void> Function(ProService) action) async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(app.pro);
      if (app.isPro && mounted) navigator.pop();
    } on PurchaseCancelled {
      // The user closed the store sheet; nothing to say.
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final features = [
      if (widget.reason != null) widget.reason!,
      ...ProFeature.values.where((f) => f != widget.reason),
    ];
    return Scaffold(
      appBar: flatAppBar(context, title: const Text('iBuild Pro')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            app.isPro ? 'You have Pro. Thank you!' : 'One purchase, yours for good.',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Free includes demo mode and one project. Pro removes the limits:',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          GroupedPanel(children: [
            for (final f in features)
              ListTile(
                leading: const Icon(Icons.check_circle, color: Palette.go),
                title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 12),
          const HintText(
              'Pro unlocks iBuild only. Build minutes and machines come from your Codemagic plan.'),
          if (_error != null) ...[
            const SizedBox(height: 14),
            ErrorNote(message: _error!),
          ],
          if (!app.isPro) ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _busy ? null : () => _run((p) => p.purchase()),
                child: Text(_price == null ? 'Unlock Pro' : 'Unlock Pro for $_price'),
              ),
            ),
            const SizedBox(height: 6),
            Text('One-time purchase. No subscription.',
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            TextButton(
              onPressed: _busy ? null : () => _run((p) => p.restore()),
              child: const Text('Restore purchase'),
            ),
            if (app.account == null)
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AccountScreen(),
                )),
                child: const Text('Sign in to keep Pro on all your devices'),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => openExternal(context, eulaUrl),
                child: const Text('Terms of Use'),
              ),
              TextButton(
                onPressed: () => openExternal(context, privacyPolicyUrl),
                child: const Text('Privacy Policy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
