import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

typedef CoverTones = ({Color primary, Color? secondary});

Color? sampleCoverAccent(Uint8List pixels) => sampleCoverTones(pixels)?.primary;

CoverTones? sampleCoverTones(Uint8List pixels) {
  final bins = List.generate(12, (_) => List.filled(4, 0.0));
  for (var i = 0; i + 3 < pixels.length; i += 4) {
    final c = Color.fromARGB(
      pixels[i + 3],
      pixels[i],
      pixels[i + 1],
      pixels[i + 2],
    );
    final hsv = HSVColor.fromColor(c),
        low = [c.r, c.g, c.b].reduce((a, b) => a < b ? a : b),
        high = hsv.value,
        delta = high - low;
    if (pixels[i + 3] < 180 || high < .12 || low > .9 || delta < .10) continue;
    final weight = delta * (.4 + high * .6),
        bin = bins[(hsv.hue / 30).floor() % 12];
    bin[0] += weight;
    bin[1] += c.r * weight;
    bin[2] += c.g * weight;
    bin[3] += c.b * weight;
  }
  final best = bins.reduce((a, b) => a[0] > b[0] ? a : b);
  if (best[0] < 1) return null;
  final index = bins.indexOf(best);
  var alternate = bins[(index + 2) % 12];
  for (var offset = 3; offset <= 10; offset++) {
    final bin = bins[(index + offset) % 12];
    if (bin[0] > alternate[0]) alternate = bin;
  }
  Color tone(List<double> bin) => Color.from(
    alpha: 1,
    red: bin[1] / bin[0],
    green: bin[2] / bin[0],
    blue: bin[3] / bin[0],
  );
  return (
    primary: tone(best),
    secondary: alternate[0] >= 1 && alternate[0] >= best[0] * .15
        ? tone(alternate)
        : null,
  );
}

Color readableCoverAccent(
  Color? sample,
  Color background,
  Color fallback, {
  bool highContrast = false,
}) {
  if (sample == null) return fallback;
  final base = background.computeLuminance(),
      dark = base < .25,
      target = highContrast ? 4.5 : 3.0;
  for (var i = 0; i <= 20; i++) {
    final tone = Color.lerp(
          sample,
          dark ? Colors.white : Colors.black,
          i / 20 * .85,
        )!,
        lum = tone.computeLuminance(),
        ratio =
            ((base > lum ? base : lum) + .05) /
            ((base < lum ? base : lum) + .05);
    if (ratio >= target) return tone;
  }
  return fallback;
}

/// Tiny decoded samples, at most32 colours. Streams detach on change/dispose.
class CoverAccentSampler {
  final _cache = <String, CoverTones?>{};
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Timer? _timer;
  int _generation = 0;
  void cancel() {
    _generation++;
    _timer?.cancel();
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void read(
    String key,
    ImageProvider provider,
    ValueChanged<Color?> complete,
  ) => readTones(key, provider, (tones) => complete(tones?.primary));

  void readTones(
    String key,
    ImageProvider provider,
    ValueChanged<CoverTones?> complete,
  ) {
    cancel();
    final generation = _generation;
    if (_cache.containsKey(key)) {
      scheduleMicrotask(() {
        if (generation == _generation) complete(_cache[key]);
      });
      return;
    }
    void finish(CoverTones? tone) {
      if (generation != _generation) return;
      cancel();
      _cache[key] = tone;
      if (_cache.length > 32) _cache.remove(_cache.keys.first);
      complete(tone);
    }

    _stream = ResizeImage.resizeIfNeeded(
      16,
      16,
      provider,
    ).resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) async {
      final image = info.image.clone();
      if (_stream != null && _listener != null) {
        _stream!.removeListener(_listener!);
      }
      _stream = null;
      _listener = null;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        finish(
          data == null ? null : sampleCoverTones(data.buffer.asUint8List()),
        );
      } catch (_) {
        finish(null);
      } finally {
        image.dispose();
      }
    }, onError: (_, _) => finish(null));
    _timer = Timer(const Duration(seconds: 5), () => finish(null));
    _stream!.addListener(_listener!);
  }

  void dispose() {
    cancel();
    _cache.clear();
  }
}
