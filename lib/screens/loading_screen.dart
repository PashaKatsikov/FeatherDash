import 'package:flutter/material.dart';

import '../game_data.dart';
import '../main.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with TickerProviderStateMixin {
  late final AnimationController _progress;
  late final AnimationController _dots;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // The bar fills gradually and reaches 100% only right before launch.
    FD.allowAll();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _goNext();
      });
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Pre-cache the heavy menu/court images, then run the bar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // Warm up a few key images while the bar animates.
    for (final p in [
      A.courts[gameState.selectedCourt],
      A.chickenStates[gameState.selectedSkin][0],
    ]) {
      // ignore: use_build_context_synchronously
      precacheImage(AssetImage(p), context);
    }
    _progress.forward();
  }

  void _goNext() {
    if (_navigated) return;
    _navigated = true;
    FD.lockPortrait();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (ctx, a, b) => FadeTransition(opacity: a, child: const MenuScreen()),
      ),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FD.navy,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                isPortrait ? A.loadingPortrait : A.loadingHorizontal,
                fit: BoxFit.cover,
              ),
              // Bottom gradient for readability.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isPortrait ? 70 : 36,
                    left: 36,
                    right: 36,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LoadingLabel(controller: _dots),
                      const SizedBox(height: 16),
                      _ProgressBar(animation: _progress),
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
        final v = animation.value;
        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return Container(
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
              ),
              child: Stack(
                children: [
                  // Fill grows left -> right.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: (w - 6) * v,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFD24A), Color(0xFFF59A2E), Color(0xFFE8612C)],
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
                        shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
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
