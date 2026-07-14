import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'boot_gate.dart' show grayArtCacheWidth;

// Connection-lost screen that overlays a tap-to-retry control on top
// of the project-specific full-bleed artwork. The art ships in two
// orientations so the layout stays meaningful in landscape too.
class OfflineScreen extends StatefulWidget {
  final WidgetBuilder rebuild;
  const OfflineScreen({super.key, required this.rebuild});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _portraitArt =
      'assets/additional_assets/nowifi_portrait.webp';
  static const String _landscapeArt =
      'assets/additional_assets/nowifi_horizontal.webp';

  late final AnimationController _haloCtl;
  late final AnimationController _tapCtl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
    _haloCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _tapCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
      lowerBound: 0.94,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android drops immersive mode after permission dialogs / overlays.
    // Re-apply on resume so the status bar doesn't creep back in.
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _haloCtl.dispose();
    _tapCtl.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    await _tapCtl.animateTo(0.94);
    await _tapCtl.animateTo(1.0);
    // Give the spinner a brief moment so the tap feels meaningful even
    // when the connection comes back almost immediately.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.rebuild),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1726),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final landscape = orientation == Orientation.landscape;
          final size = MediaQuery.sizeOf(context);
          final viewPad = MediaQuery.viewPaddingOf(context);
          // Hand-tuned per orientation:
          //  * portrait — the art's chicken sits in the lower half, so
          //    we anchor the button hard to the bottom and keep it
          //    narrow enough to leave the bird visible.
          //  * landscape — the art's chicken is centered; we push the
          //    button to the very edge to free up the middle.
          final bottomGap = (landscape ? 12.0 : 18.0) + viewPad.bottom;
          final horizontalPad =
              landscape ? size.width * 0.30 : size.width * 0.10;
          // Shares decode-width formula with BootGate's precache so the
          // image cache key matches; see comment in boot_gate.dart.
          final decodeWidth = grayArtCacheWidth(context);
          return Stack(
            fit: StackFit.expand,
            children: [
              // `cover` fills the whole screen — no letterbox strips
              // even on phones whose aspect drifts from the 9:20
              // source (e.g. 9:19.5 Pixel, 9:22 Xperia). The important
              // content — the sign at top, chicken in the middle — is
              // safely inside the central 80 % of the artwork, so the
              // small edge crop only nibbles at decorative flames /
              // coins that the user won't notice missing.
              Image.asset(
                landscape ? _landscapeArt : _portraitArt,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                width: size.width,
                height: size.height,
                cacheWidth: decodeWidth,
                filterQuality: FilterQuality.medium,
              ),
              Positioned(
                left: horizontalPad,
                right: horizontalPad,
                bottom: bottomGap,
                child: _RetryAction(
                  compact: landscape,
                  busy: _busy,
                  scale: _tapCtl,
                  halo: _haloCtl,
                  onTap: _retry,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RetryAction extends StatelessWidget {
  final bool busy;
  final bool compact;
  final AnimationController scale;
  final AnimationController halo;
  final VoidCallback onTap;
  const _RetryAction({
    required this.busy,
    required this.compact,
    required this.scale,
    required this.halo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final h = compact ? 42.0 : 48.0;
    final fs = compact ? 15.0 : 16.0;
    return Semantics(
      button: true,
      label: 'Retry connection',
      child: AnimatedBuilder(
        animation: Listenable.merge([scale, halo]),
        builder: (context, _) {
          final s = scale.value;
          final glow = 0.18 + halo.value * 0.32;
          return GestureDetector(
            onTap: busy ? null : onTap,
            child: Transform.scale(
              scale: s,
              child: Container(
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 2,
                  ),
                  gradient: busy
                      ? null
                      : const LinearGradient(
                          colors: [
                            Color(0xFFFFB74D),
                            Color(0xFFE8612C),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: busy ? Colors.black.withValues(alpha: 0.55) : null,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE8612C).withValues(alpha: glow),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: busy
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Reconnecting',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: fs,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                height: 1.0,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Try Again',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: fs + 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                height: 1.0,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x55000000),
                                    blurRadius: 3,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
