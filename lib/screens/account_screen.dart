import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../app/theme.dart';
import '../services/account_service.dart';
import '../widgets/common.dart';

/// Where the privacy policy and data deletion instructions live, so the app
/// and the store listing point at the same pages.
final privacyPolicyUrl = Uri.parse('https://adventhubsolutions.com/apps/ibuild/privacy');
final dataDeletionUrl = Uri.parse('https://adventhubsolutions.com/apps/ibuild/data-deletion');

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final account = app.account;
    return Scaffold(
      appBar: flatAppBar(context, title: const Text('Account')),
      body: account == null ? const _SignedOut() : _SignedIn(account: account),
    );
  }
}

// ------------------------------------------------------------- Signed out

class _SignedOut extends StatefulWidget {
  const _SignedOut();

  @override
  State<_SignedOut> createState() => _SignedOutState();
}

class _SignedOutState extends State<_SignedOut> {
  bool _creating = false;
  bool _busy = false;
  String? _error;
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AccountService) action) async {
    final accounts = AppScope.read(context).accounts;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(accounts);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run((a) => _creating
      ? a.signUp(
          username: _username.text,
          email: _email.text,
          password: _password.text,
        )
      : a.signIn(email: _email.text, password: _password.text));

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email above, then tap Forgot password.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await _run((a) => a.sendPasswordReset(email));
    if (_error == null) {
      messenger.showSnackBar(
          SnackBar(content: Text('If $email has an account, a reset link is on its way.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(
          'An account keeps your projects in sync across devices. It is optional: '
          'without one, everything stays on this device. Connection tokens are '
          'never synced either way.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Sign in')),
            ButtonSegment(value: true, label: Text('Create account')),
          ],
          selected: {_creating},
          onSelectionChanged: (v) => setState(() {
            _creating = v.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 20),
        if (_creating) ...[
          TextField(
            controller: _username,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: fieldDecoration(context, 'Username',
                helper: '3 to 20 letters, numbers or underscores.'),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _email,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: fieldDecoration(context, 'Email'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: (_) => _busy ? null : _submit(),
          decoration: fieldDecoration(context, 'Password',
              helper: _creating ? 'At least 8 characters.' : null),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          ErrorNote(message: _error!),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_creating ? 'Create account' : 'Sign in'),
          ),
        ),
        if (!_creating)
          TextButton(
            onPressed: _busy ? null : _reset,
            child: const Text('Forgot password'),
          ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or', style: theme.textTheme.labelMedium),
          ),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 16),
        // Apple requires Sign in with Apple on iOS whenever another social
        // sign-in is offered; Android users pick from Google or GitHub.
        if (isIos)
          _ProviderButton(
            label: 'Continue with Apple',
            icon: Icons.apple,
            onPressed: _busy ? null : () => _run((a) => a.signInWithApple()),
          ),
        _ProviderButton(
          label: 'Continue with Google',
          icon: Icons.g_mobiledata,
          onPressed: _busy ? null : () => _run((a) => a.signInWithGoogle()),
        ),
        _ProviderButton(
          label: 'Continue with GitHub',
          icon: Icons.code,
          onPressed: _busy ? null : () => _run((a) => a.signInWithGitHub()),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => openExternal(context, privacyPolicyUrl),
          child: const Text('Privacy policy'),
        ),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({required this.label, required this.icon, this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          ),
        ),
      );
}

// -------------------------------------------------------------- Signed in

class _SignedIn extends StatefulWidget {
  const _SignedIn({required this.account});
  final Account account;

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  bool _busy = false;
  String? _error;
  final _username = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _setUsername() async {
    final accounts = AppScope.read(context).accounts;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await accounts.setUsername(_username.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'This permanently deletes your account, username and synced projects. '
            'Projects saved on this device and your connection tokens stay until you '
            'remove them or uninstall iBuild. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.stop),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      try {
        await app.accounts.deleteAccount();
      } on RecentLoginRequired {
        if (!mounted) return;
        final ok = await _reauthenticate(app);
        if (!ok) return;
        await app.accounts.deleteAccount();
      }
      messenger.showSnackBar(const SnackBar(content: Text('Your account was deleted.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Firebase only deletes an account after a recent sign-in.
  Future<bool> _reauthenticate(AppController app) async {
    final usesPassword = widget.account.providers.contains('password');
    String? password;
    if (usesPassword) {
      final controller = TextEditingController();
      password = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm it is you'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (password == null) return false;
    }
    await app.accounts.reauthenticate(password: password);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final account = widget.account;
    final providers = account.providers.map(_providerName).join(', ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        GroupedPanel(children: [
          PanelRow(label: 'Username', value: account.username ?? 'Not set'),
          PanelRow(label: 'Email', value: account.email ?? 'Not shared'),
          PanelRow(label: 'Signed in with', value: providers.isEmpty ? 'Email' : providers),
        ]),
        if (account.username == null) ...[
          const SizedBox(height: 20),
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: fieldDecoration(context, 'Choose a username',
                helper: '3 to 20 letters, numbers or underscores.'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _setUsername,
            child: const Text('Save username'),
          ),
        ],
        if (app.syncError != null) ...[
          const SizedBox(height: 14),
          ErrorNote(message: app.syncError!),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          ErrorNote(message: _error!),
        ],
        const SizedBox(height: 14),
        const HintText(
            'Your projects sync to this account. Connection tokens stay on each device.'),
        const SizedBox(height: 28),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: _busy ? null : () => app.accounts.signOut(),
            child: const Text('Sign out'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: Palette.stop),
            onPressed: _busy ? null : _delete,
            child: const Text('Delete account'),
          ),
        ),
        TextButton(
          onPressed: () => openExternal(context, dataDeletionUrl),
          child: const Text('How your data is deleted'),
        ),
      ],
    );
  }

  static String _providerName(String id) => switch (id) {
        'password' => 'Email',
        'google.com' => 'Google',
        'apple.com' => 'Apple',
        'github.com' => 'GitHub',
        _ => id,
      };
}
