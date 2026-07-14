import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/browser_http.dart';
import 'local_store.dart';

typedef PushUrlListener = void Function(String url);
typedef PushTokenListener = void Function(String token);

// Channel id reused everywhere notifications are surfaced. Keep this
// string in sync with android/app/src/main/AndroidManifest.xml — the
// FCM SDK falls back to a default channel when the configured id is
// missing, and the default channel never matches the system flame icon.
const String _channelId = 'fd_blaze_alerts';
const String _channelName = 'Feather Dash Alerts';

// Background isolate handler. Must be a top-level function annotated
// with vm:entry-point so tree-shaking keeps it.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // Intentionally empty — the system tray handles display while we're
  // out of memory. The tap is processed once the process resumes.
}

class PushChannel {
  final LocalStore _store;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fcm;
  String? _token;
  bool _ready = false;

  PushUrlListener? onPushUrl;
  PushTokenListener? onTokenRotated;

  PushChannel(this._store);

  String? get token => _token;

  Future<void> bootstrap() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // No google-services.json yet — push stays disabled, app continues.
      return;
    }

    try {
      _fcm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
      await _setupLocalNotifications();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((fresh) {
        _token = fresh;
        onTokenRotated?.call(fresh);
      });

      FirebaseMessaging.onMessage.listen(_renderForegroundAlert);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      final cold = await _fcm!.getInitialMessage();
      if (cold != null) {
        _handleColdTap(cold);
      }

      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] bootstrap failed: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (_fcm == null) return false;
    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final status = settings.authorizationStatus;
    final granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    await _store.recordPushGranted(granted);
    if (status == AuthorizationStatus.denied) {
      // Android will not re-prompt — record that so the promo screen
      // stops nagging the user every 3 days.
      await _store.markPushOsRefused();
    }
    return granted;
  }

  // ----- internals -------------------------------------------------

  Future<void> _setupLocalNotifications() async {
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded['url'] is String) {
            final url = decoded['url'] as String;
            if (url.isNotEmpty) onPushUrl?.call(url);
          }
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Promotional and content updates from Feather Dash.',
          importance: Importance.high,
        ),
      );
    }
  }

  Future<void> _renderForegroundAlert(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    if (!Platform.isAndroid) return;

    AndroidNotificationDetails? details;
    final remoteImageUrl = notification.android?.imageUrl;
    if (remoteImageUrl != null && remoteImageUrl.isNotEmpty) {
      final bytes = await _downloadBytes(remoteImageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    details ??= const AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    final payload = message.data.isEmpty ? null : jsonEncode(message.data);
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  void _handleColdTap(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      // Stash for the next BootGate run to consume — the engine isn't
      // running yet, so we can't push it live.
      _store.stashInboundPush(url);
    }
  }

  void _handleWarmTap(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      // Deliberately not persisted — one-shot delivery to the live
      // WebView; the next launch should follow the standard flow.
      onPushUrl?.call(url);
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final res = await browserHttp
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }
}
