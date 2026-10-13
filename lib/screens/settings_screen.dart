import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../app/theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'project_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Settings',
            style: theme.textTheme.displaySmall
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
          ),
          const SizedBox(height: 24),
          GroupedPanel(
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(
                  app.account == null
                      ? 'Sign in or create an account'
                      : app.account!.username ?? app.account!.email ?? 'Signed in',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(app.account == null
                    ? 'Optional. Syncs your projects across devices.'
                    : 'Projects sync to this account'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AccountScreen(),
                )),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GroupedPanel(
            children: [
              SwitchListTile(
                value: app.demoMode,
                onChanged: app.setDemoMode,
                title: const Text('Demo mode',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Explore with a pretend project. Nothing is sent to Codemagic, GitHub or Apple.'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const SectionTitle('Connections'),
          GroupedPanel(
            children: [
              _ConnectionRow(
                connection: Connection.codemagic,
                title: 'Codemagic',
                connected: app.hasCodemagic,
                purpose: 'Starts builds and shows their logs',
              ),
              _ConnectionRow(
                connection: Connection.github,
                title: 'GitHub',
                connected: app.hasGitHub,
                purpose: 'Reads branches, versions and codemagic.yaml',
              ),
              _ConnectionRow(
                connection: Connection.appStoreConnect,
                title: 'App Store Connect',
                connected: app.hasAppStoreConnect,
                purpose: 'Shows TestFlight processing and tester groups',
              ),
            ],
          ),
          if (app.demoMode && (app.hasCodemagic || app.hasGitHub)) ...[
            const SizedBox(height: 8),
            const HintText('Turn off demo mode to use your connected accounts.'),
          ],
          const SizedBox(height: 28),
          SectionTitle(app.demoMode ? 'Demo projects' : 'Projects'),
          GroupedPanel(
            children: [
              for (final p in app.projects)
                ListTile(
                  title: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${p.workflowId} on ${p.branch}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ProjectSetupScreen(existing: p),
                  )),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add project'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ProjectSetupScreen(),
                )),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const HintText(
              'Tokens and keys are kept in the iOS Keychain or Android Keystore on this device and are only sent to the service they belong to.'),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.connection,
    required this.title,
    required this.connected,
    required this.purpose,
  });

  final Connection connection;
  final String title;
  final bool connected;
  final String purpose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? Palette.go : theme.colorScheme.outline,
        ),
      ),
      minLeadingWidth: 10,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(connected ? 'Connected' : purpose),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ConnectionEditorScreen(connection: connection),
      )),
    );
  }
}

class ConnectionEditorScreen extends StatefulWidget {
  const ConnectionEditorScreen({super.key, required this.connection});

  final Connection connection;

  @override
  State<ConnectionEditorScreen> createState() => _ConnectionEditorScreenState();
}

class _ConnectionEditorScreenState extends State<ConnectionEditorScreen> {
  final _token = TextEditingController();
  final _issuer = TextEditingController();
  final _keyId = TextEditingController();
  final _privateKey = TextEditingController();
  bool _prefilled = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final app = AppScope.read(context);
    _issuer.text = app.ascIssuerId;
    _keyId.text = app.ascKeyId;
  }

  @override
  void dispose() {
    _token.dispose();
    _issuer.dispose();
    _keyId.dispose();
    _privateKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final (title, intro) = switch (widget.connection) {
      Connection.codemagic => (
          'Codemagic',
          'Find your API token in Codemagic under your account settings: Integrations, then Codemagic API, then Show.',
        ),
      Connection.github => (
          'GitHub',
          'Create a fine-grained personal access token with read access to Contents and Metadata for the repositories you build. Give it write access to Contents if iBuild should commit codemagic.yaml for you.',
        ),
      Connection.appStoreConnect => (
          'App Store Connect',
          'In App Store Connect, open Users and Access, then Integrations, and create a Team Key. Developer access can read builds; App Manager is needed to create public TestFlight links.',
        ),
    };
    final connected = switch (widget.connection) {
      Connection.codemagic => app.hasCodemagic,
      Connection.github => app.hasGitHub,
      Connection.appStoreConnect => app.hasAppStoreConnect,
    };
    final error = _error;

    return Scaffold(
      appBar: flatAppBar(context, title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          HintText(intro),
          const SizedBox(height: 16),
          if (widget.connection == Connection.appStoreConnect) ...[
            TextField(
              controller: _issuer,
              autocorrect: false,
              decoration: fieldDecoration(context, 'Issuer ID'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _keyId,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: fieldDecoration(context, 'Key ID'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _privateKey,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 4,
              maxLines: 8,
              style: monoStyle(size: 12),
              decoration: fieldDecoration(
                context,
                'Private key (.p8 file contents)',
                hint: connected
                    ? 'Saved. Paste a new key to replace it.'
                    : '-----BEGIN PRIVATE KEY-----',
              ),
            ),
          ] else
            TextField(
              controller: _token,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: fieldDecoration(
                context,
                connected ? 'New token' : 'Token',
                helper: connected
                    ? 'A token is saved. Paste a new one to replace it.'
                    : null,
              ).copyWith(
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show token' : 'Hide token',
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 16),
            ErrorNote(message: error),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Save and test'),
            ),
          ),
          if (connected) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _busy ? null : _disconnect,
                style: OutlinedButton.styleFrom(foregroundColor: Palette.stop),
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = switch (widget.connection) {
        Connection.codemagic => await app.connectCodemagic(_token.text),
        Connection.github => await app.connectGitHub(_token.text),
        Connection.appStoreConnect => await app.connectAppStore(
            issuerId: _issuer.text,
            keyId: _keyId.text,
            privateKey: _privateKey.text,
          ),
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    await app.disconnect(widget.connection);
    navigator.pop();
  }
}
