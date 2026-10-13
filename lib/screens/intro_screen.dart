import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_scope.dart';
import '../models/pipeline.dart';
import '../widgets/common.dart';
import '../widgets/transit_line.dart';
import 'settings_screen.dart';

/// The web guide, optionally at one section (ids live in the gateway repo's
/// src/data/appGuides.ts).
Uri guideUrl([String? section]) => Uri.parse(
    'https://adventhubsolutions.com/apps/ibuild/guide${section == null ? '' : '#$section'}');

/// Opens the intro if it has never been shown.
void showIntroOnce(BuildContext context) {
  final app = AppScope.read(context);
  if (app.introSeen) return;
  app.markIntroSeen();
  showIntro(context);
}

Future<void> showIntro(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const IntroScreen(),
    ));

/// A few swipeable cards on first launch. Demo mode is the real tour; this
/// only points at it.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  int _page = 0;

  static final _line = PipelineSnapshot({
    Station.fetch: StationState.done,
    Station.test: StationState.done,
    Station.build: StationState.done,
    Station.upload: StationState.active,
  });

  static const _cards = [
    (
      icon: null,
      title: 'Builds from your pocket',
      body: 'Start a Codemagic build from your phone and watch it travel the line: fetch, test, build, upload, then TestFlight or Google Play.',
    ),
    (
      icon: Icons.receipt_long_outlined,
      title: 'Every step, every log',
      body: 'Open a build to read its logs as they happen, cancel it, or download the app file. History keeps every run.',
    ),
    (
      icon: Icons.groups_outlined,
      title: 'Straight to your testers',
      body: 'See when TestFlight finishes processing or which Play track has your release, and share TestFlight invitation links.',
    ),
    (
      icon: Icons.key_outlined,
      title: 'Your keys stay on your phone',
      body: 'Connect Codemagic to build your own apps; GitHub, App Store Connect and Google Play are optional. Keys stay in this device\'s secure storage. Or keep exploring the demo project first.',
    ),
  ];

  bool get _last => _page == _cards.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() => _pages.nextPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  void _connect() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const ConnectionEditorScreen(connection: Connection.codemagic),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          if (!_last)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final card in _cards)
                    ListView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                      children: [
                        SizedBox(
                          height: 120,
                          child: Center(
                            child: card.icon == null
                                ? TransitLine(snapshot: _line)
                                : CircleAvatar(
                                    radius: 48,
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    child: Icon(card.icon, size: 48,
                                        color: theme.colorScheme.onPrimaryContainer),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(card.title,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Text(card.body,
                            style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _cards.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _last ? _connect : _next,
                      child: Text(_last ? 'Connect Codemagic' : 'Next'),
                    ),
                  ),
                  if (_last) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Explore the demo'),
                      ),
                    ),
                  ],
                  TextButton(
                    onPressed: () => openExternal(context, guideUrl()),
                    child: const Text('Read the guide'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
