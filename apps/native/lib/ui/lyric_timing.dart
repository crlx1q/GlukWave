import '../core/models.dart';

/// Cues use the playback clock, including after pause, transfer and seeking.
({int active, int? countdown, bool intro}) lyricCue(
  List<Json> lines,
  bool synchronized,
  double position,
) {
  var active = -1;
  double? first;
  if (synchronized) {
    for (var index = 0; index < lines.length; index++) {
      final text = lines[index]['text']?.toString().trim() ?? '';
      if (text.isEmpty || RegExp(r'^[♪♫♬\s·.…-]+$').hasMatch(text)) continue;
      final raw = lines[index]['time'];
      if (raw is! num || !raw.isFinite) continue;
      final time = raw.toDouble();
      first ??= time;
      if (time <= position) active = index;
    }
  }
  final remaining = first != null && first > 0 ? first - position : 0.0;
  return (
    active: active,
    countdown: remaining > 0 && remaining <= 3 && active < 0
        ? remaining.ceil()
        : null,
    intro: synchronized && first != null && first > position,
  );
}

double lyricDefocus(int distance, int active) =>
    active < 0 || distance <= 1 ? 0 : ((distance - 1) * 1.15).clamp(0.0, 5.0);
