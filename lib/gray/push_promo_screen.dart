import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/network_monitor.dart';
import '../platform/local_store.dart';
import '../platform/push_channel.dart';
import '../setup/env.dart';
import 'boot_gate.dart' show grayArtCacheWidth;
import 'web_shell.dart' deferred as shell;

// Single-shot promo offering push notifications before the user lands
// in the WebView. Accept triggers the system dialog; Skip records a
// 3-day cooldown so the screen does not nag on every relaunch.
class PushPromoScreen extends StatefulWidget {
  final LocalStore store;
  final PushChannel push;
  final NetworkMonitor monitor;
  final String partnerUrl;

  const PushPromoScreen({
    super.key,
    required this.store,
    required this.push,
    required this.monitor,
    required this.partnerUrl,
  });

  @override
  State<PushPromoScreen> createState() => _PushPromoScreenState();
}

class _PushPromoScreenState extends State<PushPromoScreen>
    with WidgetsBindingObserver {
  static const String _portraitArt =
      'assets/additional_assets/notifications_portrait.webp';
  static const String _landscapeArt =
      'assets/additional_assets/notifications_horizantal.webp';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final granted = await widget.push.requestPermission();
    if (!granted) {
      // System dialog refused or unavailable — fall back to the same
      // 3-day cooldown so we don't loop on every cold start.
      final deadline = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          Env.pushPromoSkipSeconds;
      await widget.store.recordPushSkip(deadline);
    }
    if (!mounted) return;
    await _proceed();
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    final deadline = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        Env.pushPromoSkipSeconds;
    await widget.store.recordPushSkip(deadline);
    if (!mounted) return;
    await _proceed();
  }

  Future<void> _proceed() async {
    await shell.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => shell.WebShell(
          url: widget.partnerUrl,
          store: widget.store,
          push: widget.push,
          monitor: widget.monitor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111623),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final landscape = orientation == Orientation.landscape;
          final size = MediaQuery.sizeOf(context);
          final viewPad = MediaQuery.viewPaddingOf(context);
          final bottomGap = (landscape ? 14.0 : 20.0) + viewPad.bottom;
          final horizontalPad =
              landscape ? size.width * 0.28 : size.width * 0.10;
          // MUST use the same helper as BootGate's precache — otherwise
          // the cache key differs and the framework re-decodes from
          // scratch when the screen mounts, costing 1–2 s.
          final decodeWidth = grayArtCacheWidth(context);
          return Stack(
            fit: StackFit.expand,
            children: [
              // `cover` — full-bleed, no letterbox strips even when
              // the device aspect drifts from the 9:20 source. The
              // signboard and chicken sit inside the central 80 % of
              // the artwork, so the small edge crop only touches
              // decorative gold/gems.
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AcceptChip(
                      onTap: _accept,
                      busy: _busy,
                      compact: landscape,
                    ),
                    SizedBox(height: landscape ? 6 : 10),
                    _SkipChip(
                      onTap: _skip,
                      busy: _busy,
                      compact: landscape,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AcceptChip extends StatefulWidget {
  final VoidCallback onTap;
  final bool busy;
  final bool compact;
  const _AcceptChip({
    required this.onTap,
    required this.busy,
    this.compact = false,
  });

  @override
  State<_AcceptChip> createState() => _AcceptChipState();
}

class _AcceptChipState extends State<_AcceptChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.busy;
    return AnimatedBuilder(
      animation: _wave,
      builder: (context, _) {
        return GestureDetector(
          onTapDown: disabled ? null : (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: disabled
              ? null
              : (_) {
                  setState(() => _down = false);
                  widget.onTap();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            // ≥ 44 dp per Material tap-target guidelines (§13 pitfalls).
            height: widget.compact ? 48 : 54,
            transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 2.2,
              ),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF66E27A),
                  Color(0xFF1E9E55),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E9E55).withValues(
                      alpha: _down ? 0.18 : (0.22 + _wave.value * 0.32)),
                  blurRadius: _down ? 6 : 16 + _wave.value * 10,
                  spreadRadius: _down ? 0 : _wave.value * 2,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: disabled
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Accept',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.compact ? 16 : 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            height: 1.0, // kills baseline drift (§13)
                            shadows: const [
                              Shadow(
                                color: Color(0x66000000),
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
        );
      },
    );
  }
}

class _SkipChip extends StatefulWidget {
  final VoidCallback onTap;
  final bool busy;
  final bool compact;
  const _SkipChip({
    required this.onTap,
    required this.busy,
    this.compact = false,
  });

  @override
  State<_SkipChip> createState() => _SkipChipState();
}

class _SkipChipState extends State<_SkipChip> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.busy;
    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: disabled
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap();
            },
      child: AnimatedOpacity(
        opacity: _down ? 0.55 : 0.92,
        duration: const Duration(milliseconds: 90),
        child: Container(
          // ≥ 44 dp per Material tap-target guidelines (§12 pitfalls).
          height: widget.compact ? 44 : 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.4,
            ),
            color: Colors.black.withValues(alpha: 0.55),
          ),
          child: Text(
            'Skip',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.compact ? 14 : 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              height: 1.0, // kills baseline drift (§13)
              shadows: const [
                Shadow(
                  color: Color(0x55000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
