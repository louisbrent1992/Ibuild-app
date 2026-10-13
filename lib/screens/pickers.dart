import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import 'project_setup_screen.dart';

Future<void> showProjectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final app = AppScope.of(sheetContext);
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Projects',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final p in app.projects)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p.repo ?? p.codemagicAppId),
                trailing: p.id == app.project?.id
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  app.selectProject(p.id);
                },
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.add),
              title: const Text('Add project'),
              onTap: () {
                Navigator.pop(sheetContext);
                openNewProject(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> showBranchPicker(BuildContext context) async {
  final app = AppScope.read(context);
  final project = app.project;
  if (project == null) return;
  final repo = project.repo;
  final source = app.source;
  final picked = await showChoiceSheet(
    context,
    title: 'Branch',
    current: app.branch,
    loader: repo != null && source != null
        ? () => source.listBranches(repo)
        : null,
    manualHint: 'Branch name',
  );
  if (picked != null && picked.trim().isNotEmpty) {
    app.selectBranch(picked.trim());
  }
}

Future<void> showWorkflowPicker(BuildContext context) async {
  final app = AppScope.read(context);
  final project = app.project;
  if (project == null) return;
  final picked = await showChoiceSheet(
    context,
    title: 'Workflow',
    current: project.workflowId,
    loader: () => app.workflowsFor(project),
    manualHint: 'Workflow key from codemagic.yaml',
  );
  if (picked != null && picked.trim().isNotEmpty) {
    await app.updateProject(project.copyWith(workflowId: picked.trim()));
  }
}

/// A bottom sheet listing choices, with a field for typing one in.
Future<String?> showChoiceSheet(
  BuildContext context, {
  required String title,
  String? current,
  Future<List<String>> Function()? loader,
  required String manualHint,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ChoiceSheet(
      title: title,
      current: current,
      loader: loader,
      manualHint: manualHint,
    ),
  );
}

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({
    required this.title,
    required this.current,
    required this.loader,
    required this.manualHint,
  });

  final String title;
  final String? current;
  final Future<List<String>> Function()? loader;
  final String manualHint;

  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  late final Future<List<String>>? _items = widget.loader?.call();
  final _manual = TextEditingController();

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(widget.title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (items != null)
                Flexible(
                  child: FutureBuilder<List<String>>(
                    future: items,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text('${snapshot.error}'),
                        );
                      }
                      final list = snapshot.data ?? const <String>[];
                      if (list.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text('Nothing found. Type a name below.'),
                        );
                      }
                      return ListView(
                        shrinkWrap: true,
                        children: [
                          for (final item in list)
                            ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              title: Text(item),
                              trailing: item == widget.current
                                  ? Icon(Icons.check,
                                      color: theme.colorScheme.primary)
                                  : null,
                              onTap: () => Navigator.pop(context, item),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        decoration: fieldDecoration(context, widget.manualHint),
                        onSubmitted: (value) => Navigator.pop(context, value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _manual.text),
                      child: const Text('Use'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a single line of text. Returns null if dismissed.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String? initial,
  String? helper,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPrompt(
      title: title,
      label: label,
      initial: initial,
      helper: helper,
    ),
  );
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    this.initial,
    this.helper,
  });

  final String title;
  final String label;
  final String? initial;
  final String? helper;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        decoration: fieldDecoration(context, widget.label, helper: widget.helper),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
