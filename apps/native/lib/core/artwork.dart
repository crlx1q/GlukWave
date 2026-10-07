/// Request the provider's larger image only for a known public artwork URL.
/// Track metadata, source identity and small row/mini covers keep the original.
String artworkForDisplay(String original, {required bool large}) {
  if (!large) return original;
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
