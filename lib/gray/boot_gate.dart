import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dto/runtime_mode.dart';
import '../game_data.dart';
import '../main.dart' show FD, StrokeText, gameState;
import '../network/attribution_engine.dart';
import '../network/backend_client.dart';
import '../network/network_monitor.dart';
import '../platform/local_store.dart';
import '../platform/push_channel.dart';
import '../screens/menu_screen.dart';
import 'offline_screen.dart';
import 'push_promo_screen.dart';
import 'web_shell.dart' deferred as shell;

// Single entry-point of the gray flow. It plays the loading animation
// (using the title's existing court artwork so the splash matches the
// rest of the game), runs the attribution + backend pipeline, then
// hands off to either the partner WebView or the regular menu.
//
// On the first launch it persists the resolved RuntimeMode so future
// launches skip straight into the right surface.
class BootGate extends StatefulWidget {
  final LocalStore store;
  final NetworkMonitor monitor;
  final AttributionEngine attribution;
  final BackendClient backend;
  final PushChannel push;

  const BootGate({
    super.key,
    required this.store,
    required this.monitor,
    required this.attribution,
    required this.backend,
    required this.push,
  });

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _progressCtl;
  late final AnimationController _dotsCtl;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
    _progressCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
      lowerBound: 0,
      upperBound: 1,
    );
    _dotsCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Start a slow creep right away so the bar visibly fills while the
    // gray-flow pipeline runs network calls. We cap at 92% — the final
    // 8% snaps when the navigation target is decided.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _progressCtl.animateTo(0.92, curve: Curves.easeOutCubic);
      _warmAssetCache();
      _drive();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemUi() {
    // Called on the way OUT to arcade (native game) — the game screens
    // don't paint edge-to-edge and expect the status/nav bars back.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  // Decode the gray-flow art ahead of time so the navigation target
  // appears instantly. While BootGate sits waiting on AppsFlyer / the
  // backend, the CPU is idle — perfect window to prime the image cache.
  //
  // CRITICAL: the cache key MUST match what `Image.asset(..., cacheWidth: X)`
  // produces internally, otherwise the precache is wasted work. The
  // framework wraps Image.asset in `ResizeImage(AssetImage, width: X)`
  // with the default `ResizeImagePolicy.exact`. We do the exact same
  // wrapping here, and `_grayArtCacheWidth` is the single source of
  // truth shared with the screens.
  void _warmAssetCache() {
    if (!mounted) return;
    const seeds = <String>[
      'assets/additional_assets/notifications_portrait.webp',
      'assets/additional_assets/notifications_horizantal.webp',
      'assets/additional_assets/nowifi_portrait.webp',
      'assets/additional_assets/nowifi_horizontal.webp',
    ];
    final cacheW = grayArtCacheWidth(context);
    for (final asset in seeds) {
      precacheImage(
        ResizeImage(AssetImage(asset), width: cacheW),
        context,
        onError: (_, _) {},
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.push.onTokenRotated = null;
    _progressCtl.dispose();
    _dotsCtl.dispose();
    super.dispose();
  }

  Future<void> _drive() async {
    widget.push.onTokenRotated = _onTokenRotated;
    await widget.push.bootstrap();

    final mode = widget.store.currentMode();
    switch (mode) {
      case RuntimeMode.unresolved:
        await _runFirstLaunch();
        break;
      case RuntimeMode.partner:
        await _runReturningPartner();
        break;
      case RuntimeMode.arcade:
        await _runReturningArcade();
        break;
    }
  }

  // ----- first launch (resolves gray/white) ------------------------

  Future<void> _runFirstLaunch() async {
    if (!await widget.monitor.isOnline()) {
      _navOffline(firstLaunch: true);
      return;
    }

    await widget.attribution.start();
    await Future.wait([
      widget.attribution.awaitConversion(),
      widget.attribution.awaitDeepLink(),
    ]);

    final body = await widget.attribution.assembleRequestBody(
      locale: _locale(),
      pushToken: widget.push.token,
    );
    final reply = await widget.backend.deliver(body);

    if (reply.usable) {
      await widget.store.commitMode(RuntimeMode.partner);
      await _completeProgress();
      _navPartner(reply.url!);
    } else {
      await widget.store.commitMode(RuntimeMode.arcade);
      await _warmUpArcadeAssets();
      await _completeProgress();
      _navArcade();
    }
  }

  // ----- returning user, previously in partner shell ---------------

  Future<void> _runReturningPartner() async {
    if (!await widget.monitor.isOnline()) {
      await _completeProgress();
      _navOffline(firstLaunch: false);
      return;
    }

    // Cold-start push tap takes precedence over every other source —
    // when the OS hands us a URL we use it and skip the round-trip.
    final pushed = await widget.store.drainInboundPush();
    if (pushed != null) {
      await _completeProgress();
      _navPartner(pushed);
      return;
    }

    final cached = await widget.backend.cachedUrl();

    // FAST PATH: returning paid user already has a cached partner URL.
    // Show it instantly (the TZ caps loading at 10 s) and refresh the
    // URL in the background. Two outcomes from the refresh:
    //   * Backend returned the SAME url → just write a fresh expiry.
    //   * Backend ROTATED the url → hot-swap the WebView in place via
    //     the same channel push notifications use; the user sees the
    //     new content without re-launching the app.
    // Without this the splash sat for 10 s (attribution timeout) +
    // 15 s (backend POST) = up to 25 s every cold start.
    if (cached != null && cached.isNotEmpty) {
      _refreshPartnerInBackground(previousUrl: cached);
      await _completeProgress();
      _navPartner(cached);
      return;
    }

    // SLOW PATH: cached URL was wiped / never written. Fall through to
    // the full pipeline, but with tightened timeouts — the install is
    // already attributed, so the SDK callback either fires fast or not
    // at all; waiting 30 s never produced a useful answer on returning
    // launches.
    await widget.attribution.start();
    await Future.wait([
      widget.attribution.awaitConversion(timeout: const Duration(seconds: 5)),
      widget.attribution.awaitDeepLink(timeout: const Duration(seconds: 3)),
    ]);

    final body = await widget.attribution.assembleRequestBody(
      locale: _locale(),
      pushToken: widget.push.token,
    );
    final reply = await widget.backend.deliver(body);
    await _completeProgress();

    if (reply.usable) {
      _navPartner(reply.url!);
      return;
    }
    _navOffline(firstLaunch: false);
  }

  // Fire-and-forget refresh of the partner URL. Runs after BootGate
  // has already handed the user off to WebShell with the cached URL,
  // so the splash is no longer blocking.
  //
  // If the backend returns a URL that differs from what the user is
  // already viewing, we route it through `push.onPushUrl` — that's the
  // same hook WebShell wires up to handle warm push notifications, so
  // the WebView swaps to the new page live without an app restart.
  //
  // Errors are swallowed — failure here just means the next launch
  // reuses today's cached URL.
  void _refreshPartnerInBackground({required String previousUrl}) {
    Future<void>(() async {
      try {
        await widget.attribution.start();
        await Future.wait([
          widget.attribution
              .awaitConversion(timeout: const Duration(seconds: 8)),
          widget.attribution
              .awaitDeepLink(timeout: const Duration(seconds: 3)),
        ]);
        final body = await widget.attribution.assembleRequestBody(
          locale: _locale(),
          pushToken: widget.push.token,
        );
        final reply = await widget.backend.deliver(body);

        if (!reply.usable) return;
        final fresh = reply.url!;
        if (fresh == previousUrl) return; // nothing to do

        // Hot-swap. WebShell.initState registers onPushUrl; by the time
        // we get here the screen is mounted, so this fires reliably.
        final handler = widget.push.onPushUrl;
        if (handler != null) handler(fresh);
      } catch (_) {}
    });
  }

  // ----- returning user, previously in arcade ----------------------

  Future<void> _runReturningArcade() async {
    await _warmUpArcadeAssets();
    await _completeProgress();
    _navArcade();
  }

  // ----- shared helpers --------------------------------------------

  String _locale() {
    final raw = Platform.localeName;
    return raw.replaceAll('-', '_');
  }

  Future<void> _warmUpArcadeAssets() async {
    // Preload the heaviest assets the menu reaches for. Keeps the
    // first frame snappy when we navigate from here.
    for (final asset in <String>[
      A.courts[gameState.selectedCourt],
      A.chickenStates[gameState.selectedSkin][0],
      A.chickenStates[gameState.selectedSkin][2],
      A.pole,
    ]) {
      if (!mounted) return;
      await precacheImage(AssetImage(asset), context);
    }
  }

  Future<void> _completeProgress() async {
    // Snap the bar to 100% before navigating so the user always sees
    // the "we're done" frame regardless of how long the network leg took.
    await _progressCtl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  void _onTokenRotated(String fresh) {
    // Re-post in the background so the backend knows about the
    // refreshed FCM token. The fire-and-forget is intentional — we
    // don't want it to block the splash.
    widget.attribution
        .assembleRequestBody(locale: _locale(), pushToken: fresh)
        .then(widget.backend.deliver);
  }

  // ----- navigation primitives -------------------------------------

  void _navArcade() {
    if (_routed || !mounted) return;
    _routed = true;
    _restoreSystemUi();
    FD.lockPortrait();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 480),
        pageBuilder: (_, a, _) =>
            FadeTransition(opacity: a, child: const MenuScreen()),
      ),
    );
  }

  Future<void> _navPartner(String url) async {
    if (_routed || !mounted) return;
    _routed = true;
    await shell.loadLibrary();
    if (!mounted) return;

    if (widget.store.shouldShowPushPromo()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PushPromoScreen(
            store: widget.store,
            push: widget.push,
            monitor: widget.monitor,
            partnerUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => shell.WebShell(
            url: url,
            store: widget.store,
            push: widget.push,
            monitor: widget.monitor,
          ),
        ),
      );
    }
  }

  void _navOffline({required bool firstLaunch}) {
    if (_routed || !mounted) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineScreen(
          rebuild: (_) => BootGate(
            store: widget.store,
            monitor: widget.monitor,
            attribution: widget.attribution,
            backend: widget.backend,
            push: widget.push,
          ),
        ),
      ),
    );
  }

  // ----- UI --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FD.navy,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final portrait = orientation == Orientation.portrait;
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                portrait ? A.loadingPortrait : A.loadingHorizontal,
                fit: BoxFit.cover,
              ),
              // Soft bottom vignette only — keeps the bar readable
              // without darkening the artwork above it.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black45],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: portrait ? 70 : 36,
                    left: 36,
                    right: 36,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LoadingLabel(controller: _dotsCtl),
                      const SizedBox(height: 16),
                      _ProgressBar(animation: _progressCtl),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Shared decode resolution for the gray-flow art. Both BootGate's
// precache and the screen widgets' `Image.asset(cacheWidth:)` must
// pass the SAME number — otherwise the framework treats them as two
// different images and the precache is wasted.
//
// 1440 is comfortably above any phone's physical width in portrait
// (Pixel 9 = 1080, Galaxy S25 Ultra = 1440, iPhone 17 ProMax = 1206)
// so the picture is never visibly soft, while still being ~10× cheaper
// to decode than the 2160×4800 native resolution of the source WebP.
int grayArtCacheWidth(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final logical = MediaQuery.sizeOf(context).width;
  return (logical * dpr).clamp(720.0, 1440.0).round();
}

class _LoadingLabel extends StatelessWidget {
  final AnimationController controller;
  const _LoadingLabel({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final n = (controller.value * 4).floor() % 4; // 0..3 dots
        final dots = '.' * n;
        return StrokeText('Loading$dots', fontSize: 30, strokeWidth: 5);
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final Animation<double> animation;
  const _ProgressBar({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value.clamp(0.0, 1.0);
        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return Container(
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 3,
                ),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: (w - 6) * v,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFFFD24A),
                              Color(0xFFF59A2E),
                              Color(0xFFE8612C),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${(v * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
