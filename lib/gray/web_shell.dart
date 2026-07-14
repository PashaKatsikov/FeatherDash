import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../network/browser_http.dart';
import '../network/network_monitor.dart';
import '../platform/local_store.dart';
import '../platform/push_channel.dart';
import 'offline_screen.dart';

// Immersive WebView the partner content lives in. Houses every Android
// workaround the gray flow needs: keyboard scroll-into-view, safe-area
// scrub via injected CSS, redirect-loop retry, file picker bridge,
// third-party cookies, autoplay video, immersive sticky UI.
class WebShell extends StatefulWidget {
  final String url;
  final LocalStore store;
  final PushChannel push;
  final NetworkMonitor monitor;

  const WebShell({
    super.key,
    required this.url,
    required this.store,
    required this.push,
    required this.monitor,
  });

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with WidgetsBindingObserver {
  late final WebViewController _wv;
  bool _spinning = true;
  bool _offlineRouted = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;
  String? _lastMainFrameUrl;
  int _redirectAttempts = 0;

  // Rotation-mask state. The native WebView renders into a texture layer
  // that Android resizes asynchronously on orientation change: for one
  // or more frames the page is painted at the OLD width stretched into
  // the NEW height ("content fills half the screen then spreads"), then
  // reflows to the final size. Fast GPUs / recent System WebView drop
  // that intermediate frame; slow / older ones show it — which is why
  // the jitter appears only on some phones.
  //
  // We can't stop the native texture from resizing in two steps, but we
  // can cover the WebView with an opaque layer for the duration of the
  // reflow so the user never sees the intermediate frames.
  bool _rotating = false;
  bool? _lastIsLandscape;
  Timer? _rotateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // The partner content is mostly responsive in both orientations.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersive();

    _wv = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(browserHttp.userAgent)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _spinning = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _spinning = false);
          _redirectAttempts = 0;
          _patchSafeArea();
          _patchKeyboardScroll();
        },
        onWebResourceError: (err) {
          if (err.isForMainFrame != true) return;
          final desc = err.description.toLowerCase();

          // Redirect-loop retry first.
          final isLoop = err.errorCode == -1007 ||
              err.errorCode == -9 ||
              desc.contains('too_many_redirects') ||
              desc.contains('too many redirects');
          if (isLoop &&
              _lastMainFrameUrl != null &&
              _redirectAttempts < 3) {
            _redirectAttempts++;
            _wv.loadRequest(Uri.parse(_lastMainFrameUrl!));
            return;
          }

          // Cover the WebView's ugly native error page (black screen +
          // Android robot icon) instantly with our styled spinner.
          if (mounted) setState(() => _spinning = true);

          // For DNS / disconnect codes, skip the redundant DNS probe
          // inside _maybeShowOffline — go straight to OfflineScreen.
          final isDnsOrDisconnect = desc.contains('name_not_resolved') ||
              desc.contains('err_name_not_resolved') ||
              desc.contains('internet_disconnected') ||
              desc.contains('network_changed') ||
              err.errorCode == -105 ||
              err.errorCode == -106 ||
              err.errorCode == -21;
          if (isDnsOrDisconnect) {
            _routeOfflineImmediate();
          } else {
            _maybeShowOffline();
          }
        },
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          const inWebViewSchemes = <String>{
            'http', 'https', 'about', 'data', 'blob',
          };
          if (inWebViewSchemes.contains(uri.scheme)) {
            if (req.isMainFrame) _lastMainFrameUrl = req.url;
            return NavigationDecision.navigate;
          }
          _spawnExternal(uri);
          return NavigationDecision.prevent;
        },
      ))
      ..enableZoom(false);

    _configureAndroid();
    _wv.loadRequest(Uri.parse(widget.url));

    widget.push.onPushUrl = (url) {
      if (!mounted) return;
      _wv.loadRequest(Uri.parse(url));
    };

    // Debounce connectivity drops. Without the guard, flipping a VPN
    // interface briefly emits [ConnectivityResult.none] for a few
    // hundred ms before the new interface comes up — enough to flash
    // the No-Internet screen on a perfectly healthy connection.
    _connSub = widget.monitor.changes().listen((results) {
      final allNone = results.every((r) => r == ConnectivityResult.none);
      if (!allNone) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
        _routeOfflineImmediate();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final size =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    final isLandscape = size.width > size.height;
    if (_lastIsLandscape != null && isLandscape != _lastIsLandscape) {
      _maskRotation();
    }
    _lastIsLandscape = isLandscape;
  }

  // Show the opaque cover, then lift it once the WebView has had time to
  // finish its two-step texture resize + page reflow. 550 ms comfortably
  // covers slow devices; the fade-out is handled by AnimatedOpacity in
  // build(), so the reveal is smooth rather than a hard cut.
  void _maskRotation() {
    _rotateTimer?.cancel();
    if (!_rotating && mounted) setState(() => _rotating = true);
    _rotateTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _rotating = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _offlineDebounce?.cancel();
    _rotateTimer?.cancel();
    widget.push.onPushUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _maybeShowOffline() async {
    if (_offlineRouted || !mounted) return;
    if (await widget.monitor.isOnline()) return;
    if (!mounted) return;
    _routeOfflineImmediate();
  }

  // Fast-path: navigate to OfflineScreen without an extra DNS probe.
  // Used from the connectivity stream (already knows we're down) and
  // from onWebResourceError for DNS / disconnect codes.
  Future<void> _routeOfflineImmediate() async {
    if (_offlineRouted || !mounted) return;
    _offlineRouted = true;
    final current = await _wv.currentUrl() ?? widget.url;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineScreen(
          rebuild: (_) => WebShell(
            url: current,
            store: widget.store,
            push: widget.push,
            monitor: widget.monitor,
          ),
        ),
      ),
    );
  }

  void _configureAndroid() {
    if (!Platform.isAndroid) return;
    if (_wv.platform is! AndroidWebViewController) return;
    final android = _wv.platform as AndroidWebViewController;

    android.setMediaPlaybackRequiresUserGesture(false);
    android.setOnShowFileSelector(_pickFiles);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(android, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (picked == null || picked.files.isEmpty) return const [];
      return picked.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _patchKeyboardScroll() {
    // Single deferred scroll matches the keyboard animation cadence
    // without stacking another animator. behavior:'auto' is essential —
    // 'smooth' on Android races with the keyboard slide-in.
    _wv.runJavaScript(r'''
(function() {
  if (window.__fdKbPatch) return;
  window.__fdKbPatch = true;
  function isEditable(node) {
    if (!node) return false;
    if (node.isContentEditable) return true;
    var tag = node.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
  }
  function nudge() {
    var el = document.activeElement;
    if (!isEditable(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var r = el.getBoundingClientRect();
      var bottom = vp.offsetTop + vp.height;
      if (r.bottom > bottom - 18 || r.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }
  document.addEventListener('focusin', function(e) {
    if (isEditable(e.target)) setTimeout(nudge, 340);
  });
  if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var now = window.visualViewport.height;
      if (now < prev) setTimeout(nudge, 110);
      prev = now;
    });
  }
})();
''');
  }

  void _patchSafeArea() {
    // Strips the env(safe-area-inset-*) bands many partner CDNs add to
    // their layout, then removes the top spacer on the site's KNOWN
    // sticky-header classes only.
    //
    // HARD RULE (see .cursor/rules/webview_safe_area_injection.mdc):
    //   * NEVER touch padding-left / padding-right / margin on
    //     html / body / #__nuxt / #__layout / #app / #root — that
    //     destroys the site's own horizontal gutters and buttons
    //     start hitting the WebView edge.
    //   * ONLY touch padding-top / margin-top, and ONLY on classes
    //     that are unambiguously decorative headers.
    //   * The :root CSS-var overrides are safe — they only take
    //     effect when the site itself already declares them.
    _wv.runJavaScript(r'''
(function() {
  if (window.__fdSafePatch) return;
  window.__fdSafePatch = true;
  var TAG = '__fd_safe_reset';
  var CSS =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-bottom:0px!important;' +
      '--safe-left:0px!important;--safe-right:0px!important;' +
    '}' +
    '.gameview-mobile-header,.app-header,.js-safe-top{' +
      'padding-top:0!important;' +
      'margin-top:0!important;' +
    '}';
  function keyboardUp() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.78;
  }
  function apply() {
    if (keyboardUp()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta && !/viewport-fit\s*=\s*contain/i.test(meta.getAttribute('content') || '')) {
      var c = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      meta.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var node = document.getElementById(TAG);
    if (!node) {
      node = document.createElement('style');
      node.id = TAG;
      head.appendChild(node);
    }
    if (node.textContent !== CSS) node.textContent = CSS;
    if (head.lastElementChild !== node) head.appendChild(node);
  }
  apply();
  ['pushState','replaceState'].forEach(function(name) {
    var orig = history[name];
    history[name] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(apply, 60);
      setTimeout(apply, 380);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 60); });
  setInterval(apply, 2400);
})();
''');
  }

  Future<void> _spawnExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<bool> _onBack() async {
    if (await _wv.canGoBack()) {
      await _wv.goBack();
    }
    // Never let the system pop us — the back stack stays inside the WebView.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) async {
        if (!popped) await _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false, // pair with adjustResize in manifest
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: _padFor(context),
              child: WebViewWidget(controller: _wv),
            ),
            if (_spinning)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFB74D),
                    ),
                  ),
                ),
              ),
            // Rotation mask — opaque while the native WebView texture
            // resizes and the page reflows, then fades out to reveal the
            // settled layout. Matches the WebView background colour so
            // there is no visible seam. IgnorePointer keeps taps flowing
            // to the WebView the instant it's no longer covering.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_rotating,
                child: AnimatedOpacity(
                  opacity: _rotating ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  EdgeInsets _padFor(BuildContext context) {
    final mq = MediaQuery.of(context);
    final landscape = mq.orientation == Orientation.landscape;
    if (landscape) {
      // Punch out the camera notch on landscape devices.
      return EdgeInsets.only(
        left: mq.viewPadding.left,
        right: mq.viewPadding.right,
      );
    }
    return EdgeInsets.only(top: mq.viewPadding.top);
  }
}
