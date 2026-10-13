/// Only approve a challenge issued by the server currently used by this app.
/// A raw challenge code is allowed for the manual accessibility fallback.
String qrChallengeId(String value, String server) {
  final raw = value.trim(), uri = Uri.tryParse(value.trim());
  String? id;
  if (RegExp(r'^[a-zA-Z0-9_-]{8,100}$').hasMatch(raw)) {
    id = raw;
  } else if (uri != null &&
      ['http', 'https'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.origin == Uri.parse(server).origin &&
      ['/app', '/app/', '/'].contains(uri.path) &&
      uri.queryParametersAll['qr']?.length == 1) {
    id = uri.queryParameters['qr'];
  }
  if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{8,100}$').hasMatch(id)) {
    throw const FormatException('Invalid login code');
  }
  return id;
}
