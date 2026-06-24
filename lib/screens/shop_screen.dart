import 'package:flutter/material.dart';

import '../game_data.dart';
import '../main.dart';
import 'menu_screen.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    gameState.addListener(_onState);
  }

  void _onState() => setState(() {});

  @override
  void dispose() {
    gameState.removeListener(_onState);
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FD.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(A.courts[gameState.selectedCourt], fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.62)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _CircleBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                      const Spacer(),
                      const StrokeText('SHOP', fontSize: 28),
                      const Spacer(),
                      const CoinBadge(),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TabBar(
                    controller: _tab,
                    indicator: BoxDecoration(
                      color: FD.orange,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    tabs: const [
                      Tab(text: 'COURTS'),
                      Tab(text: 'SKINS'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _grid(Courts.items, 'court', gameState.ownedCourts, gameState.selectedCourt,
                          subtitle: (i) => 'Background court'),
                      _grid(Skins.items, 'skin', gameState.ownedSkins, gameState.selectedSkin,
                          subtitle: (i) => 'Chicken skin'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<ShopItem> items, String type, Set<int> owned, int selected,
      {required String Function(int) subtitle}) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.74,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final isOwned = owned.contains(item.id);
        final isSelected = selected == item.id;
        return _ShopCard(
          item: item,
          subtitle: subtitle(item.id),
          owned: isOwned,
          selected: isSelected,
          onTap: () => _onTap(type, item, isOwned, isSelected),
        );
      },
    );
  }

  void _onTap(String type, ShopItem item, bool owned, bool selected) {
    if (selected) return;
    if (owned) {
      gameState.select(type, item.id);
      return;
    }
    if (gameState.coins < item.price) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Not enough coins!'),
          backgroundColor: FD.deepOrange,
          duration: Duration(milliseconds: 1200),
        ));
      return;
    }
    if (gameState.buy(type, item.id, item.price)) {
      gameState.select(type, item.id);
    }
  }
}

class _ShopCard extends StatelessWidget {
  final ShopItem item;
  final String subtitle;
  final bool owned;
  final bool selected;
  final VoidCallback onTap;
  const _ShopCard({
    required this.item,
    required this.subtitle,
    required this.owned,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF5BE36B) : Colors.white.withValues(alpha: 0.5),
            width: selected ? 4 : 2,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(item.asset, fit: BoxFit.contain),
                ),
              ),
            ),
            Text(item.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _statusChip(),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _statusChip() {
    if (selected) {
      return _chip('SELECTED', const Color(0xFF3FAE4E), Icons.check_rounded);
    }
    if (owned) {
      return _chip('SELECT', FD.orange, Icons.touch_app_rounded);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE8612C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFFFE066), Color(0xFFF5A623)]),
            ),
            child: const Center(
              child: Text('\$', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Color(0xFF8A5A00))),
            ),
          ),
          const SizedBox(width: 6),
          Text('${item.price}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

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
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
