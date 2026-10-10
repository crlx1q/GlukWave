String? geniusLyricsUrl(String value) {
  final url = Uri.tryParse(value.trim());
  if (url == null ||
      url.scheme != 'https' ||
      !['genius.com', 'www.genius.com'].contains(url.host) ||
      url.userInfo.isNotEmpty ||
      url.hasPort) {
    return null;
  }
  final encodedPath = url
      .toString()
      .substring(url.origin.length)
      .split(RegExp(r'[?#]'))
      .first;
  if (!RegExp(
        r"^/[\w%.'-]+-lyrics/?$",
        caseSensitive: false,
      ).hasMatch(encodedPath) ||
      RegExp(
        r'%([01][0-9a-f]|2f|5c|7f)',
        caseSensitive: false,
      ).hasMatch(encodedPath) ||
      url.path.contains('\\') ||
      url.path.codeUnits.any((c) => c < 32 || c == 127)) {
    return null;
  }
  return Uri(scheme: url.scheme, host: url.host, path: url.path).toString();
}
