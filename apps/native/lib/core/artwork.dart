/// Request the provider's larger image only for a known public artwork URL.
/// Track metadata, source identity and small row/mini covers keep the original.
String artworkForDisplay(String original, {required bool large}) {
  if (!large) {
    final uri = Uri.tryParse(original);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return original;
    }
    if (RegExp(r'^i\d+\.sndcdn\.com$').hasMatch(uri.host)) {
      final path = uri.path.replaceFirst(
        RegExp(
          r'-(t500x500|t300x300|original|large)\.(jpg|jpeg|png)$',
          caseSensitive: false,
        ),
        '-large.jpg',
      );
      return uri.replace(path: path).toString();
    }
    if (['i.ytimg.com', 'img.youtube.com'].contains(uri.host) &&
        RegExp(
          r'^/vi(_webp)?/[a-zA-Z0-9_-]{11}/(maxresdefault|sddefault|hqdefault)\.(jpg|webp)$',
        ).hasMatch(uri.path)) {
      return uri
          .replace(
            path: uri.path.replaceFirst(
              RegExp(r'/(maxresdefault|sddefault|hqdefault)\.'),
              '/mqdefault.',
            ),
          )
          .toString();
    }
    return original;
  }
  final uri = Uri.tryParse(original);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      !RegExp(r'^i\d+\.sndcdn\.com$').hasMatch(uri.host)) {
    return original;
  }
  final pattern = RegExp(
    r'^(/artworks-[^/]+)-large\.(jpg|jpeg|png)$',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(uri.path);
  if (match == null) return original;
  return uri.replace(path: '${match[1]}-t500x500.${match[2]}').toString();
}
