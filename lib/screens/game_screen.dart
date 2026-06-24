import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_data.dart';
import '../main.dart';
import '../widgets/hoop.dart';

enum Phase { aiming, flying, scored, exploded, ended }

class _LiveHoop {
  final HoopConfig cfg;
  double swish = 0;
  bool justScored = false;
  _LiveHoop(this.cfg);
}

class _Floater {
  Offset pos;
  final String text;
  double age = 0;
  final Color color;
  _Floater(this.pos, this.text, this.color);
}

class _Feather {
  Offset pos;
  Offset vel;
  double rot;
  double rotSpeed;
  double age = 0;
  _Feather(this.pos, this.vel, this.rot, this.rotSpeed);
}

class GameScreen extends StatefulWidget {
  final int levelIndex;
  const GameScreen({super.key, required this.levelIndex});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late final LevelConfig level;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  // World size (set from LayoutBuilder).
  Size _size = Size.zero;
  Offset _origin = Offset.zero;

  // Max pull distance before explosion.
  // Origin sits at 72% of height, so a full pull (ratio=1.0) lands at
  // 0.72h + 0.22h = 0.94h — comfortably on-screen.
  // Explosion only triggers at 1.12× that distance (≈ 0.967h), which
  // requires deliberately going almost to the very bottom.
  double get _maxPull => _size.height * 0.22;
  static const double _explosionRatio = 1.12;

  static const double _gravity = 2200;

  Phase _phase = Phase.aiming;
  Offset _chicken = Offset.zero;
  Offset _vel = Offset.zero;
  Offset _prev = Offset.zero;
  double _spin = 0;
  double _pullRatio = 0;
  Offset? _drag;
  double _osc = 0;
  double _timeLeft = 0;
  int _score = 0;
  double _phaseTimer = 0;
  bool _paused = false;

  final List<_LiveHoop> _hoops = [];
  final List<_Floater> _floaters = [];
  final List<_Feather> _feathers = [];
  final Random _rnd = Random();

  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    level = Levels.all[widget.levelIndex];
    _timeLeft = level.timeLimit.toDouble();
    for (final h in level.hoops) {
      _hoops.add(_LiveHoop(h));
    }
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _ensureLayout(Size size) {
    if (_size == size) return;
    _size = size;
    // 72% down → leaves 28% of height below for the slingshot drag zone.
    _origin = Offset(size.width / 2, size.height * 0.72);
    if (_phase == Phase.aiming) {
      _chicken = _origin;
      _prev = _origin;
    }
  }

  Offset _hoopCenter(_LiveHoop h) {
    final w = _size.width;
    final hh = _size.height;
    final dx = sin(_osc * h.cfg.moveSpeed) * h.cfg.moveAmplitude * w;
    return Offset(h.cfg.rx * w + dx, h.cfg.ry * hh);
  }

  double _hoopWidth(_LiveHoop h) => h.cfg.sizeFactor * _size.width * 2.5;
  double _ringHalfWidth(_LiveHoop h) => h.cfg.sizeFactor * _size.width;

  void _tick(Duration now) {
    if (_last == Duration.zero) {
      _last = now;
      return;
    }
    double dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt > 0.05) dt = 0.05;
    if (_size == Size.zero) return;

    if (_phase != Phase.ended && !_paused) {
      _osc += dt;
      _update(dt);
    }
    setState(() {});
  }

  void _update(double dt) {
    // Auto-finish when the player reaches the 3-star threshold.
    if (_phase != Phase.ended && _score >= level.targetScore * 2) {
      _endGame();
      return;
    }

    // Timer.
    _timeLeft -= dt;
    if (_timeLeft <= 0) {
      _timeLeft = 0;
      _endGame();
      return;
    }

    for (final h in _hoops) {
      h.swish = max(0, h.swish - dt * 3.5);
    }

    // Floaters.
    for (final f in _floaters) {
      f.age += dt;
      f.pos = f.pos.translate(0, -40 * dt);
    }
    _floaters.removeWhere((f) => f.age > 1.1);

    // Feather particles.
    for (final f in _feathers) {
      f.age += dt;
      f.vel = f.vel.translate(0, 900 * dt);
      f.pos = f.pos + f.vel * dt;
      f.rot += f.rotSpeed * dt;
    }
    _feathers.removeWhere((f) => f.age > 1.2);

    switch (_phase) {
      case Phase.flying:
        _prev = _chicken;
        _vel = _vel.translate(0, _gravity * dt);
        _chicken = _chicken + _vel * dt;
        _spin += _vel.dx.sign * 6 * dt + 4 * dt;
        _checkScore();
        if (_phase == Phase.flying) {
          final h = _size.height;
          final w = _size.width;
          if (_chicken.dy > h + 160 || _chicken.dx < -160 || _chicken.dx > w + 160) {
            _resetChicken();
          }
        }
        break;
      case Phase.scored:
        _phaseTimer -= dt;
        _vel = _vel.translate(0, _gravity * dt);
        _chicken = _chicken + _vel * dt;
        if (_phaseTimer <= 0) _resetChicken();
        break;
      case Phase.exploded:
        _phaseTimer -= dt;
        if (_phaseTimer <= 0) _resetChicken();
        break;
      case Phase.aiming:
      case Phase.ended:
        break;
    }
  }

  void _checkScore() {
    for (final h in _hoops) {
      final c = _hoopCenter(h);
      final crossedDown = _prev.dy <= c.dy && _chicken.dy >= c.dy && _vel.dy > 0;
      if (!crossedDown) continue;
      final t = (c.dy - _prev.dy) / ((_chicken.dy - _prev.dy).abs() < 1e-6 ? 1e-6 : (_chicken.dy - _prev.dy));
      final crossX = _prev.dx + t * (_chicken.dx - _prev.dx);
      final tol = _ringHalfWidth(h) * 0.85;
      if ((crossX - c.dx).abs() <= tol) {
        _score += h.cfg.points;
        h.swish = 1.0;
        _floaters.add(_Floater(Offset(c.dx, c.dy + 10), '+${h.cfg.points}', const Color(0xFFFFE066)));
        // Snap through the net center cleanly.
        _phase = Phase.scored;
        _phaseTimer = 0.32;
        _chicken = Offset(c.dx, c.dy);
        _vel = Offset(0, max(_vel.dy, 700));
        return;
      }
    }
  }

  void _spawnFeathers(Offset at) {
    for (int i = 0; i < 14; i++) {
      final a = _rnd.nextDouble() * 2 * pi;
      final sp = 150 + _rnd.nextDouble() * 350;
      _feathers.add(_Feather(
        at,
        Offset(cos(a) * sp, sin(a) * sp - 200),
        _rnd.nextDouble() * pi,
        (_rnd.nextDouble() - 0.5) * 12,
      ));
    }
  }

  void _resetChicken() {
    _phase = Phase.aiming;
    _chicken = _origin;
    _prev = _origin;
    _vel = Offset.zero;
    _pullRatio = 0;
    _spin = 0;
    _drag = null;
  }

  void _endGame() {
    _phase = Phase.ended;
    if (!_resultShown) {
      _resultShown = true;
      final earned = gameState.completeLevel(widget.levelIndex, _score, level.targetScore);
      WidgetsBinding.instance.addPostFrameCallback((_) => _showResult(earned));
    }
  }

  // ---- Input ----
  int _stateIndex() {
    if (_phase == Phase.exploded) return 3;
    if (_phase == Phase.flying || _phase == Phase.scored) return 2;
    // Scale thresholds to the explosion ratio so all 3 stages are visible
    // before the chicken pops.
    if (_pullRatio < 0.30) return 0;  // usual
    if (_pullRatio < 0.70) return 1;  // slightly puffed
    return 2;                         // fully puffed (warning zone)
  }

  void _onPanStart(DragStartDetails d) {
    if (_phase != Phase.aiming || _paused) return;
    _drag = d.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_phase != Phase.aiming || _paused) return;
    _drag = d.localPosition;
    final pull = _drag! - _origin;
    final ratio = pull.distance / _maxPull;
    _pullRatio = ratio.clamp(0, _explosionRatio + 0.05);
    if (ratio >= _explosionRatio) {
      // Over-inflated: pop!
      _phase = Phase.exploded;
      _phaseTimer = 0.9;
      _spawnFeathers(_origin.translate(0, -40));
      _drag = null;
      _pullRatio = 0;
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_phase != Phase.aiming || _paused || _drag == null) return;
    final pull = _drag! - _origin;
    final ratio = (pull.distance / _maxPull).clamp(0, 0.98);
    if (ratio < 0.1 || pull.distance < 1) {
      _drag = null;
      _pullRatio = 0;
      return;
    }
    final dir = Offset(-pull.dx, -pull.dy) / pull.distance;
    final speed = ratio * kLaunchPower;
    _vel = dir * speed;
    _chicken = _origin;
    _prev = _origin;
    _phase = Phase.flying;
    _drag = null;
  }

  // ---- Result dialog ----
  void _showResult(int earned) {
    final won = _score >= level.targetScore;
    final hasNext = won && widget.levelIndex + 1 < Levels.all.length;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2C4474), Color(0xFF1B2A4A)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24, width: 3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeText(
                  won ? 'LEVEL CLEAR!' : 'TIME UP!',
                  fontSize: 30,
                  color: won ? const Color(0xFFFFD24A) : const Color(0xFFFF7A6B),
                ),
                const SizedBox(height: 14),
                if (won)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      final stars = gameState.starsForLevel(widget.levelIndex);
                      return Icon(
                        i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 44,
                        color: i < stars ? const Color(0xFFFFD24A) : Colors.white30,
                      );
                    }),
                  ),
                const SizedBox(height: 12),
                Text('Score: $_score / ${level.targetScore}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                if (won) ...[
                  const SizedBox(height: 6),
                  Text('+$earned coins',
                      style: const TextStyle(color: Color(0xFFFFD24A), fontSize: 16, fontWeight: FontWeight.w800)),
                ],
                const SizedBox(height: 20),
                // Home + Restart always on one row.
                Row(
                  children: [
                    Expanded(
                      child: FdButton(
                        label: '',
                        icon: Icons.home_rounded,
                        height: 56,
                        color: const Color(0xFF6C7A99),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FdButton(
                        label: '',
                        icon: Icons.refresh_rounded,
                        height: 56,
                        color: FD.orange,
                        onTap: () {
                          Navigator.pop(ctx);
                          _restart();
                        },
                      ),
                    ),
                  ],
                ),
                // NEXT button on its own row so it's always fully visible.
                if (hasNext) ...[
                  const SizedBox(height: 10),
                  FdButton(
                    label: 'NEXT LEVEL',
                    icon: Icons.arrow_forward_rounded,
                    width: double.infinity,
                    height: 56,
                    color: const Color(0xFF4CAF50),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => GameScreen(levelIndex: widget.levelIndex + 1)),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _restart() {
    setState(() {
      _resultShown = false;
      _phase = Phase.aiming;
      _score = 0;
      _timeLeft = level.timeLimit.toDouble();
      _osc = 0;
      _floaters.clear();
      _feathers.clear();
      for (final h in _hoops) {
        h.swish = 0;
      }
      _resetChicken();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FD.navy,
      body: LayoutBuilder(
        builder: (context, c) {
          _ensureLayout(Size(c.maxWidth, c.maxHeight));
          return GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(A.courts[level.courtIndex], fit: BoxFit.cover),
                ),
                Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.04))),

                // Hoops.
                for (final h in _hoops) _buildHoop(h),

                // Aim trajectory.
                if (_phase == Phase.aiming && _drag != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AimPainter(
                        origin: _origin,
                        vel: _previewVel(),
                        gravity: _gravity,
                        size: _size,
                        ratio: _pullRatio,
                      ),
                    ),
                  ),

                // Chicken.
                _buildChicken(),

                // Feather particles.
                for (final f in _feathers) _buildFeather(f),

                // Floating score texts.
                for (final f in _floaters) _buildFloater(f),

                // HUD.
                _buildHud(),

                if (_paused) _buildPauseOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }

  Offset _previewVel() {
    if (_drag == null) return Offset.zero;
    final pull = _drag! - _origin;
    final ratio = (pull.distance / _maxPull).clamp(0, 0.98);
    if (pull.distance < 1) return Offset.zero;
    final dir = Offset(-pull.dx, -pull.dy) / pull.distance;
    return dir * (ratio * kLaunchPower);
  }

  Widget _buildHoop(_LiveHoop h) {
    final c = _hoopCenter(h);
    final w = _hoopWidth(h);
    final top = c.dy - HoopWidget.ringCenterYFactor * w * HoopWidget.heightFactor;
    return Positioned(
      left: c.dx - w / 2,
      top: top,
      child: Column(
        children: [
          HoopWidget(width: w, swish: h.swish),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('+${h.cfg.points}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildChicken() {
    final stateIdx = _stateIndex();
    final asset = A.chickenStates[gameState.selectedSkin][stateIdx];
    // Bigger base size (was 0.19).
    final base = _size.width * 0.27;
    double scale;
    if (_phase == Phase.exploded) {
      scale = 1.6;
    } else if (_phase == Phase.aiming) {
      // Visual inflation: from 1× (normal) up to ~1.4× at the explosion edge.
      scale = 1.0 + (_pullRatio / _explosionRatio) * 0.40;
    } else {
      scale = 1.12; // visibly puffed during flight
    }
    final size = base * scale;
    // Red danger glow starts at 88% of explosion threshold.
    final danger = _phase == Phase.aiming && _pullRatio > _explosionRatio * 0.88;
    return Positioned(
      left: _chicken.dx - size / 2,
      top: _chicken.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: _phase == Phase.flying ? _spin : 0,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (danger)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 24,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),
              Image.asset(asset, fit: BoxFit.contain),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeather(_Feather f) {
    final op = (1 - f.age / 1.2).clamp(0.0, 1.0);
    return Positioned(
      left: f.pos.dx - 8,
      top: f.pos.dy - 8,
      child: IgnorePointer(
        child: Opacity(
          opacity: op,
          child: Transform.rotate(
            angle: f.rot,
            child: Container(
              width: 16,
              height: 9,
              decoration: BoxDecoration(
                color: const Color(0xFFF4D58A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFB78A3A), width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloater(_Floater f) {
    final op = (1 - f.age / 1.1).clamp(0.0, 1.0);
    return Positioned(
      left: f.pos.dx - 40,
      top: f.pos.dy - 20,
      width: 80,
      child: IgnorePointer(
        child: Opacity(
          opacity: op,
          child: Center(child: StrokeText(f.text, fontSize: 26, color: f.color, strokeWidth: 4)),
        ),
      ),
    );
  }

  Widget _buildHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                _circle(Icons.pause_rounded, () => setState(() => _paused = true)),
                const SizedBox(width: 10),
                _hudPill(Icons.flag_rounded, 'Lv ${level.number}'),
                const Spacer(),
                _timePill(),
              ],
            ),
            const SizedBox(height: 8),
            // Score progress toward target.
            _scoreBar(),
          ],
        ),
      ),
    );
  }

  Widget _scoreBar() {
    final t1 = level.targetScore;           // 1-star threshold
    final t2 = (t1 * 1.5).round();         // 2-star threshold
    final t3 = t1 * 2;                     // 3-star threshold (auto-finish)
    final maxV = t3.toDouble();
    final fill = (_score / maxV).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_basketball_rounded, color: Color(0xFFFF8A3D), size: 18),
              const SizedBox(width: 6),
              Text(
                '$_score',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const Spacer(),
              // Show next milestone remaining.
              Text(
                _score < t1
                    ? '${t1 - _score} to ★'
                    : _score < t2
                        ? '${t2 - _score} to ★★'
                        : _score < t3
                            ? '${t3 - _score} to ★★★'
                            : '★★★',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (ctx, c) {
              final w = c.maxWidth;
              final r1 = t1 / maxV;
              final r2 = t2 / maxV;

              return SizedBox(
                height: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Background track.
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                    ),
                    // Coloured fill.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: w * fill,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _score >= t3
                                  ? const [Color(0xFF4CAF50), Color(0xFF81C784)]
                                  : _score >= t2
                                      ? const [Color(0xFFFF9800), Color(0xFF4CAF50)]
                                      : const [Color(0xFFFFD24A), Color(0xFFFF9800)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ★ marker at t1.
                    _starMark(w, r1, 1, _score >= t1),
                    // ★★ marker at t2.
                    _starMark(w, r2, 2, _score >= t2),
                    // ★★★ marker at end.
                    _starMark(w, 1.0, 3, _score >= t3),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _starMark(double barWidth, double frac, int count, bool reached) {
    final x = barWidth * frac;
    return Positioned(
      left: x - 11,
      top: -7,
      child: Column(
        children: [
          Text(
            '★' * count,
            style: TextStyle(
              fontSize: 10,
              color: reached ? const Color(0xFFFFD24A) : Colors.white38,
              height: 1,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
            ),
          ),
          Container(
            width: 2,
            height: 20,
            color: reached ? const Color(0xFFFFD24A) : Colors.white38,
          ),
        ],
      ),
    );
  }

  Widget _timePill() {
    final danger = _timeLeft <= 10;
    final m = (_timeLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_timeLeft % 60).floor().toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: danger ? Colors.red.withValues(alpha: 0.75) : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white70, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text('$m:$s',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _hudPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white70, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _circle(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StrokeText('PAUSED', fontSize: 40),
              const SizedBox(height: 24),
              FdButton(
                label: 'RESUME',
                icon: Icons.play_arrow_rounded,
                width: 220,
                color: const Color(0xFF4CAF50),
                onTap: () => setState(() => _paused = false),
              ),
              const SizedBox(height: 14),
              FdButton(
                label: 'RESTART',
                icon: Icons.refresh_rounded,
                width: 220,
                color: FD.orange,
                onTap: () {
                  setState(() => _paused = false);
                  _restart();
                },
              ),
              const SizedBox(height: 14),
              FdButton(
                label: 'QUIT',
                icon: Icons.home_rounded,
                width: 220,
                color: const Color(0xFF6C7A99),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AimPainter extends CustomPainter {
  final Offset origin;
  final Offset vel;
  final double gravity;
  final Size size;
  final double ratio;
  _AimPainter({
    required this.origin,
    required this.vel,
    required this.gravity,
    required this.size,
    required this.ratio,
  });

  @override
  void paint(Canvas canvas, Size s) {
    if (vel == Offset.zero) return;
    final danger = ratio > 0.82;
    final color = danger ? Colors.red : Colors.white;
    final dotPaint = Paint()..color = color.withValues(alpha: 0.85);

    Offset p = origin;
    Offset v = vel;
    const dt = 0.035;
    for (int i = 0; i < 30; i++) {
      v = v.translate(0, gravity * dt);
      p = p + v * dt;
      if (p.dy > size.height || p.dx < 0 || p.dx > size.width) break;
      final r = 5.0 - i * 0.08;
      canvas.drawCircle(p, r.clamp(2, 5), dotPaint);
    }

    // Power arrow from origin.
    final dir = vel / vel.distance;
    final arrowEnd = origin + dir * (60 + ratio * 70);
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(origin, arrowEnd, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _AimPainter old) =>
      old.vel != vel || old.origin != origin || old.ratio != ratio;
}
