import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// Measured overflow with quiet pauses at both ends; no duplicate semantics.
class ScrollingLabel extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  const ScrollingLabel(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });
  @override
  State<ScrollingLabel> createState() => _ScrollingLabelState();
}

class _ScrollingLabelState extends State<ScrollingLabel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final clock = AnimationController(vsync: this);
  bool foreground = true;
  double distance = 0;
  int revision = 0;
  bool get moving =>
      foreground &&
      TickerMode.of(context) &&
      !waveVisuals(context).reducedMotion &&
      !MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => foreground = state == AppLifecycleState.resumed);
  }

  void sync(double next) {
    distance = next;
    if (next > 1 && moving) {
      final duration = Duration(
        milliseconds: ((next / 28 * 2 + 6) * 1000).round(),
      );
      if (clock.duration != duration || !clock.isAnimating) {
        clock.duration = duration;
        clock.repeat();
      }
    } else {
      clock.stop();
      clock.value = 0;
    }
  }

  @override
  void didUpdateWidget(ScrollingLabel old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      clock.stop();
      clock.value = 0;
    }
  }

  @override
  void dispose() {
    revision++;
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      final direction = Directionality.of(context);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: direction,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : painter.width;
      final overflow = math.max(0.0, painter.width - width);
      final token = ++revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && token == revision) sync(overflow);
      });
      final duration = overflow / 28 * 2 + 6;
      final pause = 1.5 / duration;
      double offset(double value) {
        if (value < pause || value >= 1 - pause) return 0;
        if (value < .5 - pause) return (value - pause) / (.5 - pause * 2);
        if (value <= .5 + pause) return 1;
        return 1 - (value - .5 - pause) / (.5 - pause * 2);
      }

      return Semantics(
        label: widget.text,
        child: ExcludeSemantics(
          child: ClipRect(
            child: SizedBox(
              width: width,
              height: painter.height,
              child: AnimatedBuilder(
                animation: clock,
                child: Text(
                  widget.text,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: widget.textAlign,
                ),
                builder: (_, child) => Transform.translate(
                  offset: Offset(-overflow * offset(clock.value), 0),
                  child: OverflowBox(
                    alignment: AlignmentDirectional.centerStart,
                    minWidth: math.max(width, painter.width),
                    maxWidth: math.max(width, painter.width),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Cover pulse follows real resolution/buffering and stops with the app lifecycle.
class TrackLoadingCover extends StatefulWidget {
  final bool loading;
  final Widget child;
  const TrackLoadingCover({
    super.key,
    required this.loading,
    required this.child,
  });
  @override
  State<TrackLoadingCover> createState() => _TrackLoadingCoverState();
}

class _TrackLoadingCoverState extends State<TrackLoadingCover>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    value: 1,
  );
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void sync() {
    if (widget.loading &&
        foreground &&
        TickerMode.of(context) &&
        !waveVisuals(context).reducedMotion &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!clock.isAnimating) clock.repeat(reverse: true);
    } else {
      clock.stop();
      clock.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(TrackLoadingCover old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: false,
    child: AnimatedBuilder(
      animation: clock,
      child: widget.child,
      builder: (_, child) => Opacity(
        key: const Key('track-loading-cover'),
        opacity: widget.loading ? .65 + .35 * clock.value : 1,
        child: Transform.scale(
          scale: widget.loading ? .975 + .025 * clock.value : 1,
          child: child,
        ),
      ),
    ),
  );
}
