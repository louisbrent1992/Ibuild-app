import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/app_scope.dart';
import 'app/theme.dart';
import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'services/account_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(accounts: await _accounts());
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

/// Accounts need Firebase, which iBuild only configures for iOS and Android.
/// Elsewhere (the Linux desktop build used in development), or if Firebase
/// fails to start, the app runs with accounts off and keeps working locally.
Future<AccountService> _accounts() async {
  final mobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  if (!mobile) return const NoAccounts();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    return FirebaseAccountService();
  } catch (e) {
    debugPrint('Accounts unavailable: $e');
    return const NoAccounts();
  }
}
