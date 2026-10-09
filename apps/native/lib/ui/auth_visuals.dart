import 'package:flutter/material.dart';
import '../l10n/wave_localizations.dart';
import '../core/appearance.dart';
import 'widgets.dart';

/// The bootstrap is safe to show before audio plugins finish initializing.
class WaveBootstrapApp extends StatelessWidget {
  const WaveBootstrapApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GlukWave',
    debugShowCheckedModeBanner: false,
    theme: buildWaveTheme(const WaveCustomization(), Brightness.light),
    darkTheme: buildWaveTheme(const WaveCustomization(), Brightness.dark),
    themeMode: ThemeMode.system,
    home: const WaveStartupPage(),
  );
}

class AuthRegisterReveal extends StatelessWidget {
  final Widget child;
  const AuthRegisterReveal({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
          waveVisuals(context).reducedMotion
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: child,
        );
}

/// The actual initialization owns this screen's lifetime. There is no splash
/// timer: it disappears as soon as the controller has restored its session.
class WaveStartupPage extends StatefulWidget {
  const WaveStartupPage({super.key});
  @override
  State<WaveStartupPage> createState() => _WaveStartupPageState();
}

class _WaveStartupPageState extends State<WaveStartupPage>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        waveVisuals(context).reducedMotion ||
        !TickerMode.of(context)) {
      motion.stop();
    } else if (!motion.isAnimating) {
      motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Scaffold(
      key: const Key('native-startup'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: motion,
                  child: const Brand(size: 48, animated: true),
                  builder: (context, child) => Transform.scale(
                    scale: 1 + motion.value * .025,
                    child: child,
                  ),
                ),
                const SizedBox(height: 38),
                SizedBox(
                  width: 104,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    borderRadius: BorderRadius.circular(2),
                    color: v.accent,
                    backgroundColor: v.line,
                  ),
                ),
                const SizedBox(height: 18),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    wt('auth.startup', context: context),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: v.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Official Google Identity brand asset; retain its shape and colors in every
/// app theme rather than adapting the mark to the user's accent color.
class GoogleIdentityMark extends StatelessWidget {
  const GoogleIdentityMark({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Image.asset('assets/google-g.png', fit: BoxFit.contain),
      ),
    ),
  );
}

class AuthAmbientWave extends StatefulWidget {
  const AuthAmbientWave({super.key});
  @override
  State<AuthAmbientWave> createState() => _AuthAmbientWaveState();
}

class _AuthAmbientWaveState extends State<AuthAmbientWave>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        waveVisuals(context).reducedMotion ||
        !TickerMode.of(context)) {
      motion.stop();
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: motion,
        builder: (context, child) => CustomPaint(
          painter: WavePainter(
            .3 + motion.value * 24,
            accentColor: v.accent,
            backgroundColor: v.background,
            style: v.waveStyle,
          ),
          child: const SizedBox(height: 150, width: double.infinity),
        ),
      ),
    );
  }
}
