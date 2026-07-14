import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../setup/attribution_keys.dart';
import '../setup/env.dart';
import 'browser_http.dart';

// Owns the AppsFlyer SDK lifecycle and exposes the merged install-time
// data that the backend uses to make its gray/white decision.
//
// Why this exists as its own class:
//   * waits for the conversion callback with a bounded timeout
//   * waits for the deep-link callback with a much shorter timeout
//   * fixes the well-known false-organic race by re-querying the GCD
//     REST endpoint when the first callback fires with
//     af_status == "Organic"
//   * never mutates or filters the attribution fields — the backend
//     parses them verbatim, missing keys hurt the routing accuracy
class AttributionEngine {
  AppsflyerSdk? _sdk;

  Map<String, dynamic> _installPayload = <String, dynamic>{};
  Map<String, dynamic> _deepLinkPayload = <String, dynamic>{};
  Map<String, dynamic> _openPayload = <String, dynamic>{};

  final Completer<void> _conversionGate = Completer<void>();
  final Completer<void> _deepLinkGate = Completer<void>();
  bool _conversionDone = false;
  bool _deepLinkDone = false;
  bool _started = false;

  bool get isStarted => _started;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final devKey = Env.attributionKey;
    if (devKey.isEmpty) {
      // Without a dev key the SDK can't do anything useful.
      // Mark the gates open so the boot pipeline doesn't stall.
      _markConversionDone();
      _markDeepLinkDone();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: Env.iosStoreId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((data) async {
      final payload = _extractPayload(data);
      if (payload.isEmpty) {
        _markConversionDone();
        return;
      }
      final status = (payload['af_status'] ?? '').toString();
      if (status.toLowerCase() == 'organic') {
        // Wait, then ask the GCD REST endpoint directly. The first
        // organic callback is frequently a lie on cold installs.
        await Future<void>.delayed(
          Duration(seconds: Env.organicRetryDelay),
        );
        final refreshed = await _fetchGcd();
        _installPayload = refreshed ?? payload;
      } else {
        _installPayload = payload;
      }
      _markConversionDone();
    });

    _sdk!.onAppOpenAttribution((data) {
      _openPayload = _extractPayload(data);
    });

    _sdk!.onDeepLinking((result) {
      try {
        final click = result.deepLink?.clickEvent;
        if (click != null) {
          _deepLinkPayload = Map<String, dynamic>.from(click);
        }
      } catch (_) {}
      _markDeepLinkDone();
    });

    try {
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Attribution] initSdk failed: $e');
      _markConversionDone();
      _markDeepLinkDone();
    }
  }

  Future<void> awaitConversion({
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _conversionGate.future.timeout(timeout, onTimeout: () {});
  }

  Future<void> awaitDeepLink({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _deepLinkGate.future.timeout(timeout, onTimeout: () {});
  }

  Future<String?> uid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  // Composes the body sent to the backend. The precedence order is
  // intentional: organic attribution wins over deep link, deep link
  // wins over plain app-open. Device-side identifiers always overwrite
  // anything from the SDK with the same key.
  Future<Map<String, dynamic>> assembleRequestBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    body.addAll(_installPayload);
    _deepLinkPayload.forEach((k, v) => body.putIfAbsent(k, () => v));
    _openPayload.forEach((k, v) => body.putIfAbsent(k, () => v));

    final id = await uid();
    body['af_id'] = id ?? '';
    body['bundle_id'] = Env.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = Env.storeId;
    body['locale'] = locale;
    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (Env.messagingSenderId.isNotEmpty) {
      body['firebase_project_id'] = Env.messagingSenderId;
    }

    if (kDebugMode) {
      debugPrint('[Attribution] body=${jsonEncode(body)}');
    }
    return body;
  }

  // ----- internals -------------------------------------------------

  Map<String, dynamic> _extractPayload(dynamic raw) {
    if (raw is Map) {
      final asMap = Map<String, dynamic>.from(raw);
      final inner = asMap['payload'];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner);
      }
      return asMap;
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> _fetchGcd() async {
    try {
      final deviceId = await uid() ?? '';
      final appId = Platform.isIOS ? Env.iosStoreId : Env.bundleId;
      final url = resolveGcdEndpoint(appId, deviceId);
      if (url.isEmpty) return null;
      final res = await browserHttp.get(
        Uri.parse(url),
        headers: {'authorization': 'Bearer ${Env.attributionKey}'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Attribution] GCD retry failed: $e');
    }
    return null;
  }

  void _markConversionDone() {
    if (_conversionDone) return;
    _conversionDone = true;
    if (!_conversionGate.isCompleted) _conversionGate.complete();
  }

  void _markDeepLinkDone() {
    if (_deepLinkDone) return;
    _deepLinkDone = true;
    if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
  }
}
