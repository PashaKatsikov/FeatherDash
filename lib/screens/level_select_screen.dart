import 'package:flutter/material.dart';

import '../game_data.dart';
import '../main.dart';
import 'game_screen.dart';
import 'menu_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(A.courts[gameState.selectedCourt], fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.55)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _BackButton(onTap: () => Navigator.pop(context)),
                      const Spacer(),
                      const StrokeText('SELECT LEVEL', fontSize: 26),
                      const Spacer(),
                      const CoinBadge(),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: Levels.all.length,
                    itemBuilder: (context, i) {
                      final unlocked = gameState.isLevelUnlocked(i);
                      final stars = gameState.starsForLevel(i);
                      return _LevelTile(
                        number: i + 1,
                        unlocked: unlocked,
                        stars: stars,
                        onTap: unlocked
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => GameScreen(levelIndex: i)),
                                );
                                setState(() {});
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  final int number;
  final bool unlocked;
  final int stars;
  final VoidCallback? onTap;
  const _LevelTile({required this.number, required this.unlocked, required this.stars, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: unlocked
                ? const [Color(0xFFFFC65C), Color(0xFFF59A2E)]
                : [Colors.grey.shade600, Colors.grey.shade800],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
          boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(0, 4), blurRadius: 0)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (unlocked)
              Text(
                '$number',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black38, offset: Offset(0, 2))],
                ),
              )
            else
              const Icon(Icons.lock_rounded, color: Colors.white, size: 26),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (s) {
                return Icon(
                  s < stars ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 13,
                  color: s < stars ? const Color(0xFFFFF06A) : Colors.white54,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 2),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
      ),
    );
  }
}
