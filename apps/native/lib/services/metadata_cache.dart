import 'dart:convert';
import 'dart:io';
import '../core/models.dart';

/// Small account-scoped shelf/search metadata, separate from audio downloads.
/// Only successful, explicitly selected read requests enter this cache.
class MetadataCache {
  static const maxEntries = 48, maxBytes = 2 * 1024 * 1024;
  final Map<String, ({int at, Json value})> _entries = {};
  File? _file;
  int _generation = 0;
  Future<void> _writes = Future.value();
  static String key(String path, [Json? query]) {
    final keys = (query ?? {}).keys.toList()..sort();
    return '$path?${jsonEncode({for (final k in keys) k: query![k]})}';
  }

  Future<void> open(Directory directory, String owner) async {
    final generation = ++_generation;
    _entries.clear();
    final safeOwner = base64Url.encode(utf8.encode(owner)).replaceAll('=', '');
    final file = File('${directory.path}/metadata-$safeOwner.json');
    _file = file;
    try {
      if (!await file.exists() || await file.length() > maxBytes) return;
      final data = object(jsonDecode(await file.readAsString()));
      if (generation != _generation) return;
      for (final row in objects(data['entries']).take(maxEntries)) {
        if (row['key'] is String && row['at'] is int && row['value'] is Map) {
          _entries[row['key']] = (at: row['at'], value: object(row['value']));
        }
      }
    } catch (_) {
      // An optional cache cannot block startup or overwrite working metadata.
    }
  }

  Json? peek(String key) => _entries[key]?.value;
  bool fresh(String key, Duration age) {
    final at = _entries[key]?.at;
    return at != null &&
        DateTime.now().millisecondsSinceEpoch - at < age.inMilliseconds;
  }

  void put(String key, Json value) {
    final cloned = object(jsonDecode(jsonEncode(value)));
    if (utf8.encode(jsonEncode(cloned)).length > maxBytes ~/ 2) return;
    _entries.remove(key);
    _entries[key] = (at: DateTime.now().millisecondsSinceEpoch, value: cloned);
    while (_entries.length > maxEntries ||
        utf8
                .encode(
                  jsonEncode(
                    _entries.values.map((entry) => entry.value).toList(),
                  ),
                )
                .length >
            maxBytes - 100) {
      _entries.remove(_entries.keys.first);
    }
    _save();
  }

  void remove(String key) {
    _entries.remove(key);
    _save();
  }

  void reset() {
    _generation++;
    _file = null;
    _entries.clear();
  }

  Future<void> clear() async {
    final file = _file;
    reset();
    await _writes;
    try {
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _save() {
    final file = _file, generation = _generation;
    if (file == null) return;
    final rows = [
      for (final entry in _entries.entries)
        {'key': entry.key, 'at': entry.value.at, 'value': entry.value.value},
    ];
    while (rows.isNotEmpty &&
        utf8.encode(jsonEncode(rows)).length > maxBytes - 100) {
      rows.removeAt(0);
    }
    final encoded = jsonEncode({'entries': rows});
    _writes = _writes.catchError((_) {}).then((_) async {
      if (generation != _generation) return;
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(encoded, flush: true);
        if (generation != _generation) {
          if (await temp.exists()) await temp.delete();
          return;
        }
        await temp.rename(file.path);
      } catch (_) {}
    });
  }

  Future<void> flush() => _writes;
}
