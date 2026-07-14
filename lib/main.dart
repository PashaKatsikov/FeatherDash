import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_data.dart';
import 'gray/boot_gate.dart';
import 'network/attribution_engine.dart';
import 'network/backend_client.dart';
import 'network/browser_http.dart';
import 'network/network_monitor.dart';
import 'platform/local_store.dart';
import 'platform/push_channel.dart';

late GameState gameState;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check come first so background isolates can attach
  // to them. Both wrapped in try/catch — the game still has to run if
  // google-services.json is missing.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Build the gray-flow service graph. All long-lived singletons live
  // here so the BootGate widget never has to construct them.
  await browserHttp.warmUp();
  final store = LocalStore();
  await store.warmUp();
  final monitor = NetworkMonitor();
  final attribution = AttributionEngine();
  final backend = BackendClient(store);
  final push = PushChannel(store);

  // Game state is the existing arcade's persistent progress. It's
  // loaded eagerly so MenuScreen has no first-frame jank.
  gameState = await GameState.load();

  runApp(FeatherDashApp(
    store: store,
    monitor: monitor,
    attribution: attribution,
    backend: backend,
    push: push,
  ));
}

class FeatherDashApp extends StatelessWidget {
  final LocalStore store;
  final NetworkMonitor monitor;
  final AttributionEngine attribution;
  final BackendClient backend;
  final PushChannel push;

  const FeatherDashApp({
    super.key,
    required this.store,
    required this.monitor,
    required this.attribution,
    required this.backend,
    required this.push,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feather Dash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF4A23E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFF1B2A4A),
      ),
      home: BootGate(
        store: store,
        monitor: monitor,
        attribution: attribution,
        backend: backend,
        push: push,
      ),
    );
  }
}

/// Shared UI helpers.
class FD {
  static const Color sky = Color(0xFF7EC8F0);
  static const Color orange = Color(0xFFF59A2E);
  static const Color deepOrange = Color(0xFFE8612C);
  static const Color brown = Color(0xFF6B4423);
  static const Color cream = Color(0xFFFFF4DC);
  static const Color navy = Color(0xFF1B2A4A);

  static void lockPortrait() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  static void allowAll() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}

/// A reusable cartoon-style button.
class FdButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color color;
  final double height;
  final double? width;
  final double fontSize;

  const FdButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = FD.orange,
    this.height = 60,
    this.width,
    this.fontSize = 22,
  });

  @override
  State<FdButton> createState() => _FdButtonState();
}

class _FdButtonState extends State<FdButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final dark = Color.alphaBlend(Colors.black.withValues(alpha: 0.30), widget.color);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: widget.width,
        height: widget.height,
        transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 3),
          boxShadow: [
            BoxShadow(
              color: dark,
              offset: Offset(0, _down ? 2 : 6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: widget.fontSize + 4),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  shadows: const [
                    Shadow(color: Colors.black38, offset: Offset(0, 2), blurRadius: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined cartoon text.
class StrokeText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color color;
  final Color strokeColor;
  final double strokeWidth;
  const StrokeText(
    this.text, {
    super.key,
    this.fontSize = 28,
    this.color = Colors.white,
    this.strokeColor = FD.brown,
    this.strokeWidth = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: color,
          ),
        ),
      ],
    );
  }
}
