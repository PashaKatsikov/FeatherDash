import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central place for asset paths so naming inconsistencies are isolated here.
class A {
  static const String iconPng = 'assets/icon.png';
  static const String loadingPortrait = 'assets/loading_screen_portrait.webp';
  static const String loadingHorizontal = 'assets/loading_screen_horizontal.webp';
  static const String pole = 'assets/basketball_pole.webp';

  static const List<String> courts = [
    'assets/basketball_court1.webp',
    'assets/basketball_court2.webp',
    'assets/basketball_court3.webp',
  ];

  static const List<String> pumps = [
    'assets/ball_pump2.webp', // default wooden pump
    'assets/ball_pump.webp', // premium dragon pump
  ];

  // Chicken states per skin index. Order: usual, slightly, puffed, exploded.
  static const List<List<String>> chickenStates = [
    [
      'assets/usual_chicken_defolt.webp',
      'assets/slightly_puffed-up_chicken_defolt.webp',
      'assets/puffed_up_chicken_defolt.webp',
      'assets/exploded_defolt_chicken.webp',
    ],
    [
      'assets/usual_chicken_skin.webp',
      'assets/slightly_puffed-up_chicken_skin.webp',
      'assets/puffed_up_chicken_skin.webp',
      'assets/exploded_chicken_skin.webp',
    ],
    [
      'assets/usual_chicken_skin2.webp',
      'assets/slightly_puffed-up_chicken_skin2.webp',
      'assets/puffed_up_chicken_skin2.webp',
      'assets/exploded_chicken_skin2.webp',
    ],
    [
      'assets/usual_chicken_skin3.webp',
      'assets/slightly_puffed-up_chicken_skin3.webp',
      'assets/puffed_up_chicken_skin3.webp',
      'assets/exploded_chicken_skin3.webp',
    ],
  ];
}

class ShopItem {
  final int id;
  final String name;
  final String asset;
  final int price;
  const ShopItem({
    required this.id,
    required this.name,
    required this.asset,
    required this.price,
  });
}

class Courts {
  static const List<ShopItem> items = [
    ShopItem(id: 0, name: 'City Court', asset: 'assets/basketball_court1.webp', price: 0),
    ShopItem(id: 1, name: 'Farm Court', asset: 'assets/basketball_court2.webp', price: 600),
    ShopItem(id: 2, name: 'Meadow Court', asset: 'assets/basketball_court3.webp', price: 1400),
  ];
}

/// Fixed launch power — no longer a purchasable item.
const double kLaunchPower = 2000.0;

class Skins {
  static const List<ShopItem> items = [
    ShopItem(id: 0, name: 'Classic Hen', asset: 'assets/usual_chicken_defolt.webp', price: 0),
    ShopItem(id: 1, name: 'Cosmic Hen', asset: 'assets/usual_chicken_skin.webp', price: 500),
    ShopItem(id: 2, name: 'Golden Hen', asset: 'assets/usual_chicken_skin2.webp', price: 1000),
    ShopItem(id: 3, name: 'Baller Hen', asset: 'assets/usual_chicken_skin3.webp', price: 1600),
  ];
}

/// A single basketball hoop placed on the court.
class HoopConfig {
  /// Relative center of the ring opening (0..1 of play area).
  final double rx;
  final double ry;

  /// Ring half-width relative to screen width (controls difficulty).
  final double sizeFactor;

  /// Horizontal oscillation amplitude (relative to width). 0 = static.
  final double moveAmplitude;

  /// Oscillation speed.
  final double moveSpeed;

  /// Points awarded for scoring in this hoop.
  final int points;

  const HoopConfig({
    required this.rx,
    required this.ry,
    this.sizeFactor = 0.16,
    this.moveAmplitude = 0,
    this.moveSpeed = 1,
    required this.points,
  });
}

class LevelConfig {
  final int index; // 0-based
  final int timeLimit; // seconds
  final int targetScore;
  final int courtIndex;
  final List<HoopConfig> hoops;

  const LevelConfig({
    required this.index,
    required this.timeLimit,
    required this.targetScore,
    required this.courtIndex,
    required this.hoops,
  });

  int get number => index + 1;
}

/// Procedurally builds 40 levels from easy to hard.
class Levels {
  static final List<LevelConfig> all = _build();

  static List<LevelConfig> _build() {
    final rnd = Random(20240624);
    final List<LevelConfig> list = [];
    for (int i = 0; i < 40; i++) {
      final t = i / 39.0; // 0..1 difficulty

      // Time shrinks from 60s -> 35s.
      final time = (60 - (t * 25)).round();

      // Number of hoops grows 1 -> 3.
      final hoopCount = i < 8
          ? 1
          : i < 20
              ? 2
              : 3;

      // Hoop size shrinks (harder to hit).
      final baseSize = (0.20 - t * 0.09);

      final hoops = <HoopConfig>[];
      for (int h = 0; h < hoopCount; h++) {
        // Spread hoops horizontally.
        final rx = hoopCount == 1
            ? 0.5
            : 0.22 + (h / (hoopCount - 1)) * 0.56;
        // Hoops sit in the upper 28–50% of the screen so the player can
        // reach them with a comfortable slingshot pull.
        final ry = 0.26 + (h % 2) * 0.06 + rnd.nextDouble() * 0.04 + t * 0.07;
        final size = (baseSize * (1 - h * 0.06)).clamp(0.09, 0.22);

        // Movement appears from level 13 onward and grows.
        final moves = i >= 12 && (h == hoopCount - 1 || i >= 22);
        final amp = moves ? (0.06 + t * 0.10) : 0.0;
        final speed = moves ? (0.8 + t * 1.6) : 1.0;

        // Smaller + higher + moving => more points.
        final difficulty = (0.22 - size) * 10 + ry * 3 + amp * 12;
        final points = (2 + difficulty).round().clamp(2, 12);

        hoops.add(HoopConfig(
          rx: rx,
          ry: ry.clamp(0.22, 0.50),
          sizeFactor: size,
          moveAmplitude: amp,
          moveSpeed: speed,
          points: points,
        ));
      }

      // Target score grows with difficulty.
      final target = (12 + i * 3).round();

      list.add(LevelConfig(
        index: i,
        timeLimit: time,
        targetScore: target,
        courtIndex: i % 3,
        hoops: hoops,
      ));
    }
    return list;
  }
}

/// Persistent player progress, backed by SharedPreferences.
class GameState extends ChangeNotifier {
  GameState(this._prefs);

  final SharedPreferences _prefs;

  static const _kCoins = 'coins';
  static const _kUnlocked = 'unlocked_levels';
  static const _kStarsPrefix = 'stars_';
  static const _kOwnedCourts = 'owned_courts';
  static const _kOwnedSkins = 'owned_skins';
  static const _kSelCourt = 'sel_court';
  static const _kSelSkin = 'sel_skin';

  static Future<GameState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return GameState(prefs);
  }

  int get coins => _prefs.getInt(_kCoins) ?? 200;
  set coins(int v) {
    _prefs.setInt(_kCoins, v);
    notifyListeners();
  }

  int get unlockedLevels => _prefs.getInt(_kUnlocked) ?? 1;

  int starsForLevel(int index) => _prefs.getInt('$_kStarsPrefix$index') ?? 0;

  bool isLevelUnlocked(int index) => index < unlockedLevels;

  Set<int> _readSet(String key, Set<int> def) {
    final list = _prefs.getStringList(key);
    if (list == null) return def;
    return list.map(int.parse).toSet();
  }

  void _writeSet(String key, Set<int> value) {
    _prefs.setStringList(key, value.map((e) => e.toString()).toList());
  }

  Set<int> get ownedCourts => _readSet(_kOwnedCourts, {0});
  Set<int> get ownedSkins => _readSet(_kOwnedSkins, {0});

  int get selectedCourt => _prefs.getInt(_kSelCourt) ?? 0;
  int get selectedSkin => _prefs.getInt(_kSelSkin) ?? 0;

  void addCoins(int amount) {
    coins = coins + amount;
  }

  bool buy(String type, int id, int price) {
    if (coins < price) return false;
    coins = coins - price;
    switch (type) {
      case 'court':
        final s = ownedCourts..add(id);
        _writeSet(_kOwnedCourts, s);
        break;
      case 'skin':
        final s = ownedSkins..add(id);
        _writeSet(_kOwnedSkins, s);
        break;
    }
    notifyListeners();
    return true;
  }

  void select(String type, int id) {
    switch (type) {
      case 'court':
        _prefs.setInt(_kSelCourt, id);
        break;
      case 'skin':
        _prefs.setInt(_kSelSkin, id);
        break;
    }
    notifyListeners();
  }

  /// Record a level result. Returns coins earned.
  int completeLevel(int index, int score, int target) {
    final won = score >= target;
    if (!won) return 0;

    // Stars: 1 for win, 2 for >=1.5x target, 3 for >=2x target.
    int stars = 1;
    if (score >= target * 2) {
      stars = 3;
    } else if (score >= (target * 1.5).round()) {
      stars = 2;
    }

    final prevStars = starsForLevel(index);
    if (stars > prevStars) {
      _prefs.setInt('$_kStarsPrefix$index', stars);
    }

    if (index + 1 >= unlockedLevels && index + 1 < Levels.all.length) {
      _prefs.setInt(_kUnlocked, index + 2);
    }

    // Coins: base + bonus for first clear / extra stars.
    final firstClear = prevStars == 0;
    final earned = (40 + index * 4) + (firstClear ? 60 : 0) + stars * 15;
    addCoins(earned);
    return earned;
  }
}
