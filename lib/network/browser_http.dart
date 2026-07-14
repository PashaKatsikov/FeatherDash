import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../cipher/scrambler.dart';

// HTTP transport that always presents a believable mobile-browser
// User-Agent. The default Dart UA is a strong fingerprint that
// attribution networks penalise, so we override it on every request
// and also reuse the same string for the WebView's setUserAgent call.

class BrowserHttpClient extends http.BaseClient {
  BrowserHttpClient._();

  static final BrowserHttpClient _instance = BrowserHttpClient._();
  factory BrowserHttpClient() => _instance;

  final http.Client _delegate = http.Client();
  String _userAgent = 'Mozilla/5.0';
  bool _ready = false;

  String get userAgent => _userAgent;
  bool get isReady => _ready;

  // Call once during bootstrap, before any HTTP work.
  Future<void> warmUp() async {
    if (_ready) return;
    try {
      final chrome = _chromeVersionFragment();
      final webkit = _webkitVersionFragment();
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        // ★ MUST be the user-facing Android release ("14", "15"),
        //   NOT the API level (34, 35). Real Chrome writes the
        //   release; sdkInt would instantly out us as a shell.
        final release = info.version.release.isNotEmpty
            ? info.version.release
            : '14';
        _userAgent = 'Mozilla/5.0 (Linux; Android $release; '
            '${info.brand} ${info.model} Build/${_buildTag(info)}) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/537.36';
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        final osTag = info.systemVersion.replaceAll('.', '_');
        _userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS $osTag like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${info.systemVersion} Mobile/15E148 Safari/$webkit';
      }
    } catch (_) {
      // Device info isn't available on every host (tests, etc.). The
      // fallback UA is still better than the default Dart one.
      _userAgent = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/${_chromeVersionFragment()} Mobile Safari/537.36';
    } finally {
      _ready = true;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _userAgent);
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();

  // ----- helpers ---------------------------------------------------

  String _buildTag(dynamic info) {
    final display = info.display as String? ?? '';
    if (display.isNotEmpty) return display;
    final id = info.id as String? ?? '';
    return id.isNotEmpty ? id : 'AP3A.240905.015.A2';
  }

  String _chromeVersionFragment() {
    // ★ Chrome major version MUST be current when the app ships.
    //   Stale majors (e.g. Chrome/132 in Jul 2026) are trivially
    //   fingerprinted as "old shell". Bump this per project — see
    //   graypart_template/.cursor/rules/gray_user_agent.mdc §1.
    //   Plaintext: 149.0.7392.104
    final v = unscramble(const <int>[
      0x2f, 0x94, 0x3a, 0x8b, 0x77, 0xaf, 0x5a, 0xac,
      0xb8, 0x6d, 0xf5, 0x50, 0xba, 0xc5,
    ]);
    return v.isEmpty ? '149.0.7392.104' : v;
  }

  String _webkitVersionFragment() {
    final v = unscramble(const <int>[
      0x28, 0x90, 0x36, 0x8b, 0x76, 0xaf, 0x5c, 0xaa,
    ]);
    return v.isEmpty ? '605.1.15' : v;
  }
}

final BrowserHttpClient browserHttp = BrowserHttpClient();
