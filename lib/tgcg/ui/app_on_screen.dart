import 'package:flutter/widgets.dart';

/// Whether the app can be seen: screens that refresh on a timer skip their
/// turn while it is in the background or its browser tab is hidden, so a
/// million phones on election day do not ask the server for screens nobody
/// is looking at. A visible window without focus (a Situation Room wall
/// display) still counts as on screen.
bool get appOnScreen => switch (WidgetsBinding.instance.lifecycleState) {
  null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  _ => false,
};
