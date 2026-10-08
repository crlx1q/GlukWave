import '../l10n/wave_localizations.dart';
import 'dart:math' as math;

typedef Json = Map<String, dynamic>;
Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
double number(dynamic value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

// The server uses epoch milliseconds; older clients also accepted ISO dates.
DateTime challengeExpiry(dynamic value) {
  if (value is num && value.isFinite && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const FormatException('Invalid authentication expiry');
}

class WaveTrack {
  final Json json;
  WaveTrack(Json data) : json = Map.of(data);
  String get id => json['id'] as String;
  String get title => json['title'] as String? ?? wt('native.32b74a3c47');
  String get artist => json['artist'] as String? ?? '';
  String get album => json['album'] as String? ?? '';
  String get artwork => json['artwork'] as String? ?? '';
  String get source => json['source'] as String? ?? 'local';
  String get sourceUrl => json['sourceUrl'] as String? ?? '';
  double get duration => number(json['duration']);
  Json get playback => object(json['playback']);
  bool get playable => playback['kind'] == 'audio';
  bool get offline => playback['offline'] == true && playable;
  String get sourceName => switch (source) {
    'youtube' => 'YouTube',
    'spotify' => 'Spotify',
    'soundcloud' => 'SoundCloud',
    'yandex' => wt('native.0fb8bc0888'),
    _ => wt('native.8df71302b3'),
  };
}

class WaveUser {
  final Json json;
  WaveUser(this.json);
  String get id => json['id'] as String;
  String get displayName =>
      json['displayName'] as String? ??
      json['username'] as String? ??
      wt('native.6d15d36f74');
  String get username => json['username'] as String? ?? '';
  String get email => json['email'] as String? ?? '';
  String get avatar => json['avatarUrl'] as String? ?? '';
  String get banner => json['bannerUrl'] as String? ?? '';
  String get bio => json['bio'] as String? ?? '';
  String get plan => json['plan'] as String? ?? 'free';
  bool get admin => json['role'] == 'admin';
  List<String> get tags => List<String>.from(json['tags'] ?? []);
}

class PlaybackSnapshot {
  final String? trackId;
  final double position, volume;
  final bool playing;
  final List<String> queue;
  final int updatedAt, revision;
  const PlaybackSnapshot({
    this.trackId,
    this.position = 0,
    this.volume = .8,
    this.playing = false,
    this.queue = const [],
    this.updatedAt = 0,
    this.revision = 0,
  });
  factory PlaybackSnapshot.fromJson(Json j) => PlaybackSnapshot(
    trackId: j['trackId'] as String?,
    position: number(j['position']),
    volume: number(j['volume'], .8).clamp(0, 1),
    playing: j['playing'] == true,
    queue: List<String>.from(j['queue'] ?? []),
    updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
    revision: (j['revision'] as num?)?.toInt() ?? 0,
  );
  double projectedPosition(int now, {double? duration}) {
    var p = position + (playing ? math.max(0, now - updatedAt) / 1000 : 0);
    if (duration != null && duration > 0) p = math.min(p, duration);
    return math.max(0, p);
  }

  Json toJson() => {
    'trackId': trackId,
    'position': position,
    'volume': volume,
    'playing': playing,
    'queue': queue,
    'updatedAt': updatedAt,
    'revision': revision,
  };
}

bool mayControlRoom(Json room, String userId) =>
    room['ownerId'] == userId ||
    objects(
      room['members'],
    ).any((m) => m['userId'] == userId && m['canControl'] == true);

String clock(double seconds) {
  final n = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final minutes = n ~/ 60, ss = (n % 60).toString().padLeft(2, '0');
  return n >= 3600
      ? '${n ~/ 3600}:${(minutes % 60).toString().padLeft(2, '0')}:$ss'
      : '$minutes:$ss';
}

/// LRC stores total minutes and fractions, independent of display formatting.
String lrcClock(double seconds) {
  final milliseconds = seconds.isFinite && seconds > 0
      ? (seconds * 1000).round()
      : 0;
  return '${(milliseconds ~/ 60000).toString().padLeft(2, '0')}:${(milliseconds ~/ 1000 % 60).toString().padLeft(2, '0')}.${(milliseconds % 1000).toString().padLeft(3, '0')}';
}

int activeLyric(List<Json> lines, double position) {
  for (var i = lines.length - 1; i >= 0; i--) {
    if (number(lines[i]['time'], double.infinity) <= position) return i;
  }
  return -1;
}
