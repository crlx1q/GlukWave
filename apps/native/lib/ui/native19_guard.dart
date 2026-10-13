import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'motion_icons.dart';
import 'native19_strings.dart';
import 'widgets.dart';

Future<void> showWaveGuard(BuildContext context, WaveController controller) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => WaveGuardPage(controller: controller)),
    );

/// A phone approves a specific desktop challenge; scanning never signs in by itself.
class WaveGuardPage extends StatefulWidget {
  final WaveController controller;
  const WaveGuardPage({super.key, required this.controller});
  @override
  State<WaveGuardPage> createState() => _WaveGuardPageState();
}

class _WaveGuardPageState extends State<WaveGuardPage>
    with WidgetsBindingObserver {
  final scanner = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  final manual = TextEditingController();
  bool scanning = false, busy = false, done = false, entering = false;
  Json? target;
  String? pendingValue, error;
  Timer? expiry;
  WaveController get c => widget.controller;
  bool get phone => [
    TargetPlatform.android,
    TargetPlatform.iOS,
  ].contains(defaultTargetPlatform);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(accountChanged);
  }

  void accountChanged() {
    if (!mounted || c.loggedIn) return;
    expiry?.cancel();
    unawaited(stopScanner());
    setState(() {
      scanning = false;
      target = null;
      pendingValue = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(stopScanner());
    } else if (scanning && !busy && c.loggedIn) {
      unawaited(scanner.start().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(accountChanged);
    expiry?.cancel();
    unawaited(scanner.dispose());
    manual.dispose();
    super.dispose();
  }

  Future<void> start() async {
    if (!c.loggedIn || busy) return;
    expiry?.cancel();
    setState(() {
      scanning = true;
      entering = false;
      error = null;
      target = null;
      done = false;
    });
    try {
      await scanner.start();
    } catch (_) {
      if (mounted) setState(() => error = nativeText(context, 'cameraDetail'));
    }
  }

  Future<void> stopScanner() async {
    try {
      await scanner.stop();
    } catch (_) {
      // A camera shutdown failure must not block the manual fallback.
    }
  }

  Future<void> inspect(String value) async {
    if (!c.loggedIn || busy || value.trim().isEmpty) return;
    expiry?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    await stopScanner();
    try {
      final info = await c.qrInfo(value.trim());
      if (mounted && c.loggedIn) {
        setState(() {
          target = info;
          pendingValue = value.trim();
          scanning = false;
          entering = false;
        });
        if (info['expiresAt'] != null) {
          final remaining = challengeExpiry(
            info['expiresAt'],
          ).difference(DateTime.now());
          expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
            if (!mounted) return;
            setState(() {
              target = null;
              pendingValue = null;
              entering = true;
              error = wt('native.b85fd36bb6', context: context);
            });
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          scanning = false;
          entering = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> approve() async {
    if (!c.loggedIn || pendingValue == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await c.approveQr(pendingValue!);
      if (mounted && c.loggedIn) {
        expiry?.cancel();
        setState(() {
          done = true;
          target = null;
          pendingValue = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget cameraErrorCard() => Surface(
    padding: const EdgeInsets.all(20),
    child: Column(
      key: const Key('guard-camera-error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const WaveControlIcon(Icons.qr_code_scanner_rounded, size: 36),
        const SizedBox(height: 16),
        Text(
          nativeText(context, 'camera'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          nativeText(context, 'cameraDetail'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: waveVisuals(context).muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('guard-camera-retry'),
          onPressed: start,
          child: Text(
            nativeText(context, 'cameraRetry'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const WaveControlIcon(Icons.arrow_back_rounded),
        ),
        title: const Brand(compact: true, size: 27),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WaveControlIcon(
                      done
                          ? Icons.shield_outlined
                          : Icons.qr_code_scanner_rounded,
                      size: 38,
                      color: v.accent,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      nativeText(
                        context,
                        done
                            ? 'approved'
                            : target != null
                            ? 'confirmLogin'
                            : 'guard',
                      ),
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      nativeText(
                        context,
                        done
                            ? 'approvedDetail'
                            : target != null
                            ? 'confirmDetail'
                            : 'guardDetail',
                      ),
                      style: TextStyle(
                        color: v.muted,
                        height: 1.65,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (!c.loggedIn)
                      Text(wt('native.4c922f0c45', context: context))
                    else if (done)
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(nativeText(context, 'backPlayer')),
                      )
                    else if (target != null) ...[
                      Surface(
                        child: Row(
                          children: [
                            WaveControlIcon(
                              Icons.devices_rounded,
                              color: v.accent,
                              size: 30,
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                target!['deviceName']?.toString() ?? 'GlukWave',
                                key: const Key('guard-target-name'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('guard-approve'),
                          onPressed: busy ? null : approve,
                          child: Text(nativeText(context, 'approve')),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  expiry?.cancel();
                                  target = null;
                                  pendingValue = null;
                                }),
                          child: Text(nativeText(context, 'cancel')),
                        ),
                      ),
                    ] else ...[
                      if (scanning && phone)
                        ValueListenableBuilder<MobileScannerState>(
                          valueListenable: scanner,
                          builder: (_, state, _) {
                            // Permission/error copy sizes to the user's text scale;
                            // only a working camera owns the fixed viewfinder height.
                            if (state.error != null) return cameraErrorCard();
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(
                                v.corners(26),
                              ),
                              child: SizedBox(
                                height: bounds.maxHeight < 650 ? 220 : 300,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    MobileScanner(
                                      controller: scanner,
                                      onDetect: (capture) {
                                        final value = capture
                                            .barcodes
                                            .firstOrNull
                                            ?.rawValue;
                                        if (value != null) {
                                          unawaited(inspect(value));
                                        }
                                      },
                                      errorBuilder: (_, _) =>
                                          const SizedBox.shrink(),
                                    ),
                                    const IgnorePointer(
                                      child: Padding(
                                        padding: EdgeInsets.all(40),
                                        child: CustomPaint(
                                          painter: _ScanFrame(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      if (scanning)
                        ValueListenableBuilder<MobileScannerState>(
                          valueListenable: scanner,
                          builder: (_, state, _) => state.error != null
                              ? const SizedBox(height: 12)
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    nativeText(context, 'scanFrame'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: v.muted,
                                    ),
                                  ),
                                ),
                        ),
                      if (!scanning && phone && !entering)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('guard-scan'),
                            onPressed: start,
                            icon: const WaveControlIcon(
                              Icons.qr_code_scanner_rounded,
                              size: 19,
                            ),
                            label: Text(nativeText(context, 'scan')),
                          ),
                        ),
                      if (entering || !phone) ...[
                        TextField(
                          key: const Key('guard-manual-code'),
                          controller: manual,
                          maxLength: 1024,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: nativeText(context, 'manualLabel'),
                          ),
                          onSubmitted: busy ? null : inspect,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const Key('guard-inspect'),
                            onPressed: busy ? null : () => inspect(manual.text),
                            child: Text(nativeText(context, 'checking')),
                          ),
                        ),
                      ],
                      if (entering && phone)
                        Center(
                          child: TextButton.icon(
                            key: const Key('guard-scan-again'),
                            onPressed: busy ? null : start,
                            icon: const WaveControlIcon(
                              Icons.qr_code_scanner_rounded,
                              size: 18,
                            ),
                            label: Text(nativeText(context, 'scanAgain')),
                          ),
                        ),
                      Center(
                        child: TextButton(
                          key: const Key('guard-manual'),
                          onPressed: busy
                              ? null
                              : () {
                                  unawaited(stopScanner());
                                  setState(() {
                                    entering = true;
                                    scanning = false;
                                  });
                                },
                          child: Text(nativeText(context, 'manual')),
                        ),
                      ),
                    ],
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Row(
                          children: [
                            WavePlaybackIcon(
                              playing: false,
                              loading: true,
                              size: 21,
                              color: v.accent,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              nativeText(context, 'checking'),
                              style: TextStyle(color: v.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              height: 1.6,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanFrame extends CustomPainter {
  const _ScanFrame();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final p = Path();
    const length = 24.0;
    for (final x in [0.0, size.width]) {
      for (final y in [0.0, size.height]) {
        p.moveTo(x, y + (y == 0 ? length : -length));
        p.lineTo(x, y);
        p.lineTo(x + (x == 0 ? length : -length), y);
      }
    }
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(_ScanFrame oldDelegate) => false;
}
