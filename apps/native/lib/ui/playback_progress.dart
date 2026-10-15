import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/controller.dart';
import 'theme.dart';

/// Isolated visual time. No frame can seek audio, broadcast, or notify the app.
class ProgressFrame {
  final double position, duration, rate;
  final bool playing, live;
  final Object? scope, stamp;
  final int horizon;
  const ProgressFrame({
    required this.position,
    required this.duration,
    required this.playing,
    this.rate = 1,
    this.live = false,
    this.scope,
    this.stamp,
    this.horizon = 2000,
  });
}

class ProgressPresentationClock {
  ProgressFrame? _sample;
  int _at = 0;
  double position(ProgressFrame frame, int physicalMilliseconds) {
    final old = _sample;
    if (old == null ||
        old.scope != frame.scope ||
        old.stamp != frame.stamp ||
        old.position != frame.position ||
        old.playing != frame.playing ||
        old.rate != frame.rate ||
        old.duration != frame.duration) {
      _sample = frame;
      _at = physicalMilliseconds;
    }
    final elapsed = frame.playing && !frame.live
        ? (physicalMilliseconds - _at).clamp(0, frame.horizon) * frame.rate
        : 0.0;
    return (frame.position + elapsed).clamp(
      0,
      frame.duration > 0 ? frame.duration : 0,
    );
  }

  bool moving(ProgressFrame frame, int now) =>
      frame.playing &&
      position(frame, now) < frame.duration &&
      (frame.live || now - _at < frame.horizon);
}

class SmoothProgressBuilder extends StatefulWidget {
  final ProgressFrame Function() read;
  final Stream<dynamic>? updates;
  final Widget Function(BuildContext, double, double) builder;
  const SmoothProgressBuilder({
    super.key,
    required this.read,
    this.updates,
    required this.builder,
  });
  @override
  State<SmoothProgressBuilder> createState() => _SmoothProgressBuilderState();
}

class _SmoothProgressBuilderState extends State<SmoothProgressBuilder>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final physical = Stopwatch()..start();
  final clock = ProgressPresentationClock();
  late final Ticker ticker = createTicker((_) => draw());
  StreamSubscription<dynamic>? subscription;
  Timer? reducedTimer;
  ScrollPosition? scroll;
  bool foreground = true, inView = true, reduced = false;
  int lastPaint = -1000;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground = [
      null,
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
    ].contains(WidgetsBinding.instance.lifecycleState);
    listen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sync();
    });
  }

  void listen() {
    subscription?.cancel();
    subscription = widget.updates?.listen((_) {
      if (mounted) {
        setState(() {});
        sync();
      }
    });
  }

  void checkView() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      inView = rect.overlaps(Offset.zero & MediaQuery.sizeOf(context));
    }
  }

  void sync() {
    if (!mounted) return;
    checkView();
    final enabled =
        foreground &&
        inView &&
        TickerMode.of(context) &&
        clock.moving(widget.read(), physical.elapsedMilliseconds);
    if (enabled && !reduced && !ticker.isActive) ticker.start();
    if ((!enabled || reduced) && ticker.isActive) ticker.stop();
    if (enabled && reduced && reducedTimer == null) {
      reducedTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => draw(),
      );
    }
    if ((!enabled || !reduced) && reducedTimer != null) {
      reducedTimer?.cancel();
      reducedTimer = null;
    }
  }

  void scrolled() {
    sync();
    if (inView && foreground) setState(() {});
  }

  void draw() {
    final now = physical.elapsedMilliseconds;
    if (!reduced || now - lastPaint >= 100) {
      lastPaint = now;
      setState(() {});
    }
    sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced =
        waveVisuals(context).reducedMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    final next = Scrollable.maybeOf(context)?.position;
    if (scroll != next) {
      scroll?.removeListener(scrolled);
      scroll = next;
      scroll?.addListener(scrolled);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sync();
    });
  }

  @override
  void didUpdateWidget(SmoothProgressBuilder old) {
    super.didUpdateWidget(old);
    if (old.updates != widget.updates) listen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    sync();
    if (foreground) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    reducedTimer?.cancel();
    scroll?.removeListener(scrolled);
    ticker.dispose();
    physical.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.read();
    return widget.builder(
      context,
      clock.position(frame, physical.elapsedMilliseconds),
      frame.duration,
    );
  }
}

class PlaybackProgress extends StatelessWidget {
  final WaveController controller;
  final Widget Function(BuildContext, double, double) builder;
  const PlaybackProgress({
    super.key,
    required this.controller,
    required this.builder,
  });
  ProgressFrame read() {
    final c = controller,
        audio = c.audio,
        remote = audio.remote,
        embedded = audio.current?.embedded == true,
        state = audio.playbackState.value;
    final selected = audio.viewCurrent;
    if (!remote && selected != null && selected.id != audio.current?.id) {
      return ProgressFrame(
        scope: '${c.controlScope}:${selected.id}',
        position: 0,
        duration: selected.duration * 1000,
        playing: false,
        stamp: selected.id,
      );
    }
    return ProgressFrame(
      scope: '${c.controlScope}:${audio.viewCurrent?.id}',
      position: remote
          ? state.updatePosition.inMilliseconds.toDouble()
          : audio.outputPosition.inMilliseconds.toDouble(),
      duration:
          audio.duration?.inMilliseconds.toDouble() ??
          (audio.viewCurrent?.duration ?? 0) * 1000,
      playing:
          audio.playing &&
          !c.trackLoading &&
          c.transferPending == null &&
          (remote || audio.sourceReady),
      live: !remote && !embedded,
      rate: remote || c.room != null ? 1 : audio.player.speed,
      stamp: remote
          ? state.updateTime
          : embedded
          ? audio.provider.position
          : null,
      horizon: remote ? 5000 : 2000,
    );
  }

  @override
  Widget build(BuildContext context) => SmoothProgressBuilder(
    read: read,
    updates: controller.audio.positionStream,
    builder: builder,
  );
}
