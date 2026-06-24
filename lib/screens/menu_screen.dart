import 'dart:math';
import 'package:flutter/material.dart';

import '../game_data.dart';
import '../main.dart';
import 'level_select_screen.dart';
import 'shop_screen.dart';
import 'webview_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bob;

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    gameState.addListener(_onState);
  }

  void _onState() => setState(() {});

  @override
  void dispose() {
    gameState.removeListener(_onState);
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(A.courts[gameState.selectedCourt], fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.28)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const CoinBadge(),
                      const Spacer(),
                      _IconBtn(
                        icon: Icons.privacy_tip_rounded,
                        label: 'Privacy',
                        onTap: () => _openWeb('Privacy Policy', 'https://feattherdash.com/privacy-policy.html'),
                      ),
                      const SizedBox(width: 10),
                      _IconBtn(
                        icon: Icons.support_agent_rounded,
                        label: 'Support',
                        onTap: () => _openWeb('Support', 'https://feattherdash.com/support.html'),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: _bob,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, sin(_bob.value * pi) * 8 - 4),
                      child: child,
                    );
                  },
                  child: Column(
                    children: [
                      Transform.rotate(
                        angle: -0.04,
                        child: const StrokeText('FEATHER', fontSize: 56, strokeWidth: 8, color: Color(0xFFFFE08A)),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -8),
                        child: const StrokeText('DASH', fontSize: 64, strokeWidth: 8, color: Color(0xFFFFB23E)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Image.asset(
                  A.chickenStates[gameState.selectedSkin][2],
                  height: 150,
                ),
                const Spacer(),
                FdButton(
                  label: 'PLAY',
                  icon: Icons.play_arrow_rounded,
                  width: 240,
                  height: 70,
                  fontSize: 28,
                  color: const Color(0xFF4CAF50),
                  onTap: () => _go(const LevelSelectScreen()),
                ),
                const SizedBox(height: 16),
                FdButton(
                  label: 'SHOP',
                  icon: Icons.storefront_rounded,
                  width: 240,
                  height: 64,
                  color: FD.orange,
                  onTap: () => _go(const ShopScreen()),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _go(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => setState(() {}));
  }

  void _openWeb(String title, String url) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebViewScreen(title: title, url: url)));
  }
}

class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white70, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFFFE066), Color(0xFFF5A623)]),
            ),
            child: const Center(
              child: Text('\$', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF8A5A00))),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${gameState.coins}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white70, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
