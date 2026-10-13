import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/api.dart';
import '../core/models.dart';

class MusicCache extends ChangeNotifier {
  final WaveApi api;
  final Future<Directory> Function() supportDirectory;
  late Directory directory;
  Json entries = {};
  final Map<String, double> progress = {};
  final Map<String, Future<void>> _jobs = {};
  final Map<String, CancelToken> _tokens = {};
  final Set<String> _cancelled = {};
  final Map<String, String> failures = {};
  bool ready = false;
  Future<void> _serial = Future.value();
  Future<void> _downloadTail = Future.value();
  int limitMB = 1024;
  String? activeId;
  MusicCache(this.api, {Future<Directory> Function()? supportDirectory})
    : supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  int get bytes => entries.values.fold<int>(
    0,
    (sum, e) =>
        sum +
        ['bytes', 'coverBytes', 'lyricsBytes'].fold<int>(
          0,
          (n, key) => n + ((object(e)[key] as num?)?.toInt() ?? 0),
        ),
  );
  bool contains(String id) => entries.containsKey(id);
  List<WaveTrack> get savedTracks => entries.entries
      .where((entry) => object(object(entry.value)['track'])['id'] == entry.key)
      .map((entry) => WaveTrack(object(object(entry.value)['track'])))
      .toList();
  String? failureFor(String id) => failures[id];
  void queueDownload(String id) {
    _cancelled.remove(id);
    failures.remove(id);
    progress.putIfAbsent(id, () => 0);
    notifyListeners();
  }

  bool downloadCancelled(String id) => _cancelled.contains(id);
  void finishQueuedDownload(String id) {
    if (!_jobs.containsKey(id)) progress.remove(id);
    notifyListeners();
  }

  void cancel(String id) {
    _cancelled.add(id);
    _tokens[id]?.cancel();
  }

  String? _sidecar(String id, String key) {
    if (!ready) return null;
    final name = object(entries[id])[key];
    if (name is! String || p.basename(name) != name) return null;
    return p.join(directory.path, name);
  }

  String? artworkPath(String id) => _sidecar(id, 'cover');
  String? artworkForUrl(String url) {
    for (final entry in entries.entries) {
      if (object(object(entry.value)['track'])['artwork'] == url) {
        return artworkPath(entry.key);
      }
    }
    return null;
  }

  // Downloads are files, never an HLS playlist or an HTTP error document.
  // Only inspect the prefix; unknown binary containers go to the decoder.
  Future<bool> _isAudioFile(File file) async {
    if (await file.length() == 0) return false;
    final handle = await file.open();
    try {
      final prefix = utf8
          .decode(await handle.read(256), allowMalformed: true)
          .replaceFirst(RegExp(r'^\uFEFF'), '')
          .trimLeft();
      return !RegExp(
        r'^(?:#EXTM3U|<!doctype\b|<html\b|<\?xml\b|[\[{])',
        caseSensitive: false,
      ).hasMatch(prefix);
    } finally {
      await handle.close();
    }
  }

  // All metadata, eviction, quota checks and manifest writes are serialized.
  // Network I/O stays outside the lock so downloads can run concurrently.
  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final predecessor = _serial, release = Completer<void>();
    _serial = release.future;
    await predecessor;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<void> open(String namespace) async {
    await Future.wait(
      _jobs.values.map((job) => job.catchError((_) {})).toList(),
    );
    await _exclusive(() async {
      directory = Directory(
        p.join((await supportDirectory()).path, 'music', namespace),
      );
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, 'manifest.json'));
      try {
        entries = await file.exists()
            ? object(jsonDecode(await file.readAsString()))
            : {};
      } catch (_) {
        entries = {};
      }
      for (final id in entries.keys.toList()) {
        final name = object(entries[id])['file'];
        if (name is! String ||
            p.basename(name) != name ||
            !await File(p.join(directory.path, name)).exists()) {
          entries.remove(id);
        }
      }
      ready = true;
      failures.clear();
      await _saveUnlocked();
    });
  }

  Future<void> _saveUnlocked() async {
    final temp = File(p.join(directory.path, 'manifest.tmp'));
    await temp.writeAsString(jsonEncode(entries), flush: true);
    await temp.rename(p.join(directory.path, 'manifest.json'));
    notifyListeners();
  }

  Future<File?> fileFor(String id) => _exclusive(() async {
    final entry = object(entries[id]);
    if (entry.isEmpty) return null;
    final name = entry['file'];
    if (name is! String || p.basename(name) != name) {
      entries.remove(id);
      await _saveUnlocked();
      return null;
    }
    final file = File(p.join(directory.path, name));
    if (!await file.exists() || !await _isAudioFile(file)) {
      await _removeUnlocked(id);
      await _saveUnlocked();
      return null;
    }
    entry['usedAt'] = DateTime.now().millisecondsSinceEpoch;
    entries[id] = entry;
    await _saveUnlocked();
    return file;
  });
  Future<void> save(WaveTrack track, {bool manual = false}) async {
    if (!track.offline) {
      throw WaveException(wt('native.1a9e0219dd'));
    }
    if (contains(track.id)) {
      if (manual) {
        await _exclusive(() async {
          final entry = object(entries[track.id]);
          if (entry.isNotEmpty) {
            entry['manual'] = true;
            entry['track'] = track.json;
            entries[track.id] = entry;
            await _saveUnlocked();
          }
        });
        // Older app versions only persisted audio. Pinning them now fills in
        // durable art without downloading the audio again.
        if (ready &&
            object(entries[track.id])['cover'] == null &&
            !_tokens.containsKey(track.id)) {
          final token = CancelToken();
          _tokens[track.id] = token;
          try {
            await _saveCover(track, token);
          } finally {
            if (identical(_tokens[track.id], token)) _tokens.remove(track.id);
          }
        }
      }
      return;
    }
    if (_jobs.containsKey(track.id)) {
      await _jobs[track.id];
      if (manual && contains(track.id)) {
        await save(track, manual: true);
      }
      return;
    }
    _cancelled.remove(track.id);
    failures.remove(track.id);
    final token = CancelToken();
    _tokens[track.id] = token;
    progress[track.id] = 0;
    final task = _downloadTail.catchError((_) {}).then((_) async {
      if (token.isCancelled || _cancelled.contains(track.id)) return;
      await _download(track, manual, token);
    });
    _downloadTail = task.catchError((_) {});
    _jobs[track.id] = task;
    notifyListeners();
    try {
      await task;
    } catch (error) {
      if (!token.isCancelled) failures[track.id] = error.toString();
      rethrow;
    } finally {
      _jobs.remove(track.id);
      _tokens.remove(track.id);
      progress.remove(track.id);
      notifyListeners();
    }
  }

  Future<void> _download(
    WaveTrack track,
    bool manual,
    CancelToken token,
  ) async {
    final filename =
        '${base64Url.encode(utf8.encode(track.id)).replaceAll('=', '')}.audio';
    final temp = File(p.join(directory.path, '$filename.part'));
    try {
      await api.download(
        track,
        temp,
        cancelToken: token,
        progress: (value) {
          if (value != 1 &&
              progress.containsKey(track.id) &&
              (value - progress[track.id]!).abs() < .01) {
            return;
          }
          progress[track.id] = value;
          notifyListeners();
        },
      );
      if (!await _isAudioFile(temp)) {
        await temp.delete();
        throw WaveException(
          wt('native.c11b18779a'),
          'AUDIO_FORMAT_UNAVAILABLE',
        );
      }
    } catch (error) {
      if (await temp.exists()) await temp.delete();
      if (token.isCancelled) {
        return;
      }
      rethrow;
    }
    await _exclusive(() async {
      if (_cancelled.contains(track.id) || token.isCancelled) {
        if (await temp.exists()) {
          await temp.delete();
        }
        return;
      }
      final size = await temp.length();
      final victims =
          entries.keys
              .where(
                (id) => object(entries[id])['manual'] != true && id != activeId,
              )
              .toList()
            ..sort(
              (a, b) => number(
                object(entries[a])['usedAt'],
              ).compareTo(number(object(entries[b])['usedAt'])),
            );
      for (final id in victims) {
        if (bytes + size <= limitMB * 1024 * 1024) {
          break;
        }
        await _removeUnlocked(id);
      }
      if (bytes + size > limitMB * 1024 * 1024) {
        await temp.delete();
        await _saveUnlocked();
        throw WaveException(wt('native.7e606ff748'));
      }
      await temp.rename(p.join(directory.path, filename));
      entries[track.id] = {
        'file': filename,
        'bytes': size,
        'manual': manual,
        'usedAt': DateTime.now().millisecondsSinceEpoch,
        'track': track.json,
      };
      await _saveUnlocked();
    });
    if (contains(track.id) && !token.isCancelled) {
      await _saveCover(track, token);
    }
  }

  Future<void> _saveCover(WaveTrack track, CancelToken token) async {
    if (track.artwork.isEmpty) return;
    final address = Uri.tryParse(api.url(track.artwork));
    if (address == null ||
        !['https', 'http'].contains(address.scheme) ||
        address.userInfo.isNotEmpty) {
      return;
    }
    final name =
        '${base64Url.encode(utf8.encode(track.id)).replaceAll('=', '')}.cover';
    final folder = directory.path;
    try {
      final response = await api.dio.get<ResponseBody>(
        address.toString(),
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          receiveTimeout: const Duration(seconds: 10),
          headers: address.origin == Uri.parse(api.server).origin
              ? api.headers
              : null,
        ),
      );
      final body = response.data;
      if (body == null) return;
      final picture = <int>[];
      await for (final part in body.stream) {
        if (picture.length + part.length > 2 * 1024 * 1024) {
          throw const FormatException('Cover too large');
        }
        picture.addAll(part);
      }
      final image =
          picture.length >= 12 &&
          ((picture[0] == 137 &&
                  picture[1] == 80 &&
                  picture[2] == 78 &&
                  picture[3] == 71) ||
              (picture[0] == 255 && picture[1] == 216) ||
              String.fromCharCodes(picture.take(3)) == 'GIF' ||
              String.fromCharCodes(picture.take(4)) == 'RIFF' &&
                  String.fromCharCodes(picture.skip(8).take(4)) == 'WEBP');
      if (!image) return;
      await _exclusive(() async {
        if (token.isCancelled ||
            _cancelled.contains(track.id) ||
            directory.path != folder ||
            !contains(track.id)) {
          return;
        }
        if (bytes + picture.length > limitMB * 1024 * 1024) return;
        final file = File(p.join(folder, name));
        await file.writeAsBytes(picture, flush: true);
        final entry = object(entries[track.id]);
        entry['cover'] = name;
        entry['coverBytes'] = picture.length;
        entries[track.id] = entry;
        await _saveUnlocked();
      });
    } catch (_) {
      /* An unavailable picture never invalidates a saved audio file. */
    }
  }

  Future<void> saveLyrics(String id, Json lyrics) async {
    if (!ready || !contains(id) || objects(lyrics['lines']).isEmpty) return;
    await _exclusive(() async {
      if (!ready || !contains(id)) return;
      final encoded = jsonEncode(lyrics), size = utf8.encode(encoded).length;
      if (size > 256 * 1024) return;
      final entry = object(entries[id]),
          name =
              '${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}.lyrics.json';
      if (bytes - ((entry['lyricsBytes'] as num?)?.toInt() ?? 0) + size >
          limitMB * 1024 * 1024) {
        return;
      }
      await File(
        p.join(directory.path, name),
      ).writeAsString(encoded, flush: true);
      entry['lyrics'] = name;
      entry['lyricsBytes'] = size;
      entries[id] = entry;
      await _saveUnlocked();
    });
  }

  Future<Json?> lyricsFor(String id) async {
    final path = _sidecar(id, 'lyrics');
    if (path == null) return null;
    try {
      final file = File(path);
      if (await file.length() > 256 * 1024) return null;
      return object(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeUnlocked(String id) async {
    final entry = object(entries.remove(id));
    if (entry.isNotEmpty) {
      final name = entry['file'];
      final file = name is String && p.basename(name) == name
          ? File(p.join(directory.path, name))
          : null;
      if (file != null && await file.exists()) {
        await file.delete();
      }
      for (final key in ['cover', 'lyrics']) {
        final name = entry[key];
        if (name is String && p.basename(name) == name) {
          final extra = File(p.join(directory.path, name));
          if (await extra.exists()) await extra.delete();
        }
      }
    }
    failures.remove(id);
  }

  Future<void> remove(String id) async {
    _cancelled.add(id);
    _tokens[id]?.cancel();
    if (activeId == id) {
      throw WaveException(wt('native.9c8269d22d'));
    }
    await _exclusive(() async {
      await _removeUnlocked(id);
      await _saveUnlocked();
    });
  }

  Future<void> clear({bool includingDownloads = false}) async {
    _cancelled.addAll(_jobs.keys);
    _cancelled.addAll(progress.keys);
    for (final token in _tokens.values) {
      token.cancel();
    }
    await Future.wait(
      _jobs.values.map((job) => job.catchError((_) {})).toList(),
    );
    progress.clear();
    await _exclusive(() async {
      for (final id in entries.keys.toList()) {
        if (id != activeId &&
            (includingDownloads || object(entries[id])['manual'] != true)) {
          await _removeUnlocked(id);
        }
      }
      for (final file in directory.listSync().whereType<File>()) {
        if (file.path.endsWith('.part')) {
          await file.delete();
        }
      }
      await _saveUnlocked();
    });
  }
}
