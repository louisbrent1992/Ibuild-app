import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/app_scope.dart';
import 'app/theme.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.load();
  runApp(IBuildApp(controller: controller));
}

class IBuildApp extends StatelessWidget {
  const IBuildApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'iBuild',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeShell(),
      ),
    );
  }
}
