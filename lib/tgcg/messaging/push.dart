import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/backend.dart';
import 'inbox_page.dart';

/// App notifications through Firebase Cloud Messaging.
///
/// Only Android builds made with the Firebase project's values receive them:
/// `--dart-define=TGCG_FIREBASE_API_KEY=...`, `TGCG_FIREBASE_APP_ID`,
/// `TGCG_FIREBASE_SENDER_ID` and `TGCG_FIREBASE_PROJECT_ID`. Without them, or
/// on other devices, notifications stay off; the inbox still holds every
/// message.
class PushNotifications {
  PushNotifications._();

  static const _apiKey = String.fromEnvironment('TGCG_FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('TGCG_FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('TGCG_FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('TGCG_FIREBASE_PROJECT_ID');

  static bool get available =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty;

  static bool _initialized = false;
  static String? _token;
  static StreamSubscription<String>? _refreshed;

  static Future<FirebaseMessaging?> _messaging() async {
    if (!available) return null;
    if (!_initialized) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      _initialized = true;
    }
    return FirebaseMessaging.instance;
  }

  /// Registers this phone for the signed-in account's notifications.
  static Future<void> start(BackendServices services) async {
    try {
      final messaging = await _messaging();
      if (messaging == null) return;
      await messaging.requestPermission();
      // The server sends to FCM registration tokens (HTTP v1 `token`), so this
      // keeps the token calls that version 17 deprecates for installation ids.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null) return;
      _token = token;
      await _refreshed?.cancel();
      // ignore: deprecated_member_use
      _refreshed = messaging.onTokenRefresh.listen((fresh) {
        _token = fresh;
        unawaited(services.messaging.registerDevice(fresh, 'android').catchError((Object _) {}));
      });
      await services.messaging.registerDevice(token, 'android');
    } catch (_) {
      // Notifications stay off; messages still reach the inbox.
    }
  }

  /// This phone stops receiving the account's notifications (on signing out,
  /// while the session still works).
  static Future<void> stop(BackendServices services) async {
    final refreshed = _refreshed;
    _refreshed = null;
    await refreshed?.cancel();
    final token = _token;
    if (token == null) return;
    _token = null;
    try {
      await services.messaging.unregisterDevice(token);
    } catch (_) {
      // Signing out goes ahead: once Firebase deletes the token, the server
      // drops it at the next message.
    }
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static Stream<RemoteMessage> get received =>
      available && _initialized ? FirebaseMessaging.onMessage : const Stream.empty();

  static Stream<RemoteMessage> get opened =>
      available && _initialized ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();

  static Future<RemoteMessage?> openedFirst() async =>
      available && _initialized ? FirebaseMessaging.instance.getInitialMessage() : null;
}

/// Registers the phone after signing in, shows a notification that arrives
/// while the app is open, and opens the inbox from one that is tapped.
class PushRegistration extends StatefulWidget {
  const PushRegistration({super.key, required this.child});

  final Widget child;

  @override
  State<PushRegistration> createState() => _PushRegistrationState();
}

class _PushRegistrationState extends State<PushRegistration> {
  final _subscriptions = <StreamSubscription<RemoteMessage>>[];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = TgcgBackend.of(context);
    if (services == null || !PushNotifications.available) return;
    unawaited(_start(services));
  }

  Future<void> _start(BackendServices services) async {
    await PushNotifications.start(services);
    if (!mounted) return;
    _subscriptions
      ..add(PushNotifications.received.listen(_show))
      ..add(PushNotifications.opened.listen((_) => _openInbox()));
    if (await PushNotifications.openedFirst() != null && mounted) _openInbox();
  }

  void _openInbox() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const InboxPage()),
  );

  void _show(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [?notification.title, ?notification.body].where((part) => part.isNotEmpty).join('\n'),
        ),
        action: SnackBarAction(label: 'Open', onPressed: _openInbox),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
