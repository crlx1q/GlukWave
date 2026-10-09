import 'models.dart';

/// A public server snapshot. OAuth credentials never enter the native client.
class DiscordConnection {
  final Json json;
  final DateTime receivedAt;
  DiscordConnection(Json data, {DateTime? receivedAt})
    : json = Map.unmodifiable(data),
      receivedAt = receivedAt ?? DateTime.now();

  bool get eligible => json['eligible'] == true;
  bool get configured => json['configured'] == true;
  bool get connected => json['connected'] == true;
  bool get needsReconnect => json['needsReconnect'] == true;
  bool get enabled => json['enabled'] == true;
  bool get allowJoin => json['allowJoin'] == true;
  static const statuses = {
    'unavailable',
    'disconnected',
    'reconnect_required',
    'disabled',
    'idle',
    'publishing',
    'active',
    'retrying',
    'unsupported',
    'locked',
  };
  String get status => statuses.contains(json['status'])
      ? json['status'] as String
      : 'unavailable';
  Json get identity => object(json['identity']);
  String get displayName => _text(identity['displayName']);
  String get username => _text(identity['username']);
  String get avatar => _text(identity['avatarUrl']);
  Json get activity => object(json['activity']);
  String get title => _text(activity['title']);
  String get artist => _text(activity['artist']);
  String get album => _text(activity['album']);
  String get cover => _text(activity['cover']);
  String get deviceName => _text(object(json['device'])['name']);
  bool get playing => activity['playing'] == true;
  double get duration => _finite(activity['duration']);
  String? get trackUrl => _webUrl(activity['trackUrl']);
  String? get joinUrl => _webUrl(activity['joinUrl']);
  double positionAt(DateTime now) {
    final elapsed = playing
        ? now.difference(receivedAt).inMilliseconds / 1000
        : 0;
    final value =
        (_finite(activity['position']) + elapsed.clamp(0, double.infinity));
    return duration > 0 ? value.clamp(0, duration) : value;
  }

  static String _text(dynamic value) => value is String ? value : '';
  static double _finite(dynamic value) => value is num && value.isFinite
      ? value.toDouble().clamp(0, double.infinity)
      : 0;
  static String? _webUrl(dynamic value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            ['https', 'http'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? value
        : null;
  }
}
