import 'package:flutter/widgets.dart';
import 'package:sheetal_driver_app/state/driver_session.dart';

class DriverScope extends InheritedNotifier<DriverSession> {
  const DriverScope({
    super.key,
    required DriverSession session,
    required super.child,
  }) : super(notifier: session);

  static DriverSession of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DriverScope>();
    assert(scope != null, 'DriverScope is missing');
    return scope!.notifier!;
  }
}
