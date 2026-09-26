import 'package:flutter/widgets.dart';

import 'app_controller.dart';

/// Makes the [AppController] available below it and rebuilds dependents
/// when it changes.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Reads the controller and rebuilds the caller when it changes.
  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!.notifier!;
  }

  /// Reads the controller without subscribing. Use in callbacks.
  static AppController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!.notifier!;
  }
}
