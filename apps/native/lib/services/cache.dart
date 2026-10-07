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
  late Directory directory;
  Json entries = {};
  final Map<String, double> progress = {};
  final Map<String, Future<void>> _jobs = {};
  final Map<String, CancelToken> _tokens = {};
  final Set<String> _cancelled = {};
  Future<void> _serial = Future.value();
  int limitMB = 1024;
  String? activeId;
  MusicCache(this.api);
  int get bytes => entries.values.fold<int>(
    0,
    (sum, e) => sum + ((object(e)['bytes'] as num?)?.toInt() ?? 0),
  );
  bool contains(String id) => entries.containsKey(id);

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
        p.join(
          (await getApplicationSupportDirectory()).path,
          'music',
          namespace,
        ),
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
    final file = File(p.join(directory.path, entry['file'] as String));
    if (!await file.exists()) {
      entries.remove(id);
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
            entries[track.id] = entry;
            await _saveUnlocked();
          }
        });
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
    final token = CancelToken();
    _tokens[track.id] = token;
    final task = _download(track, manual, token);
    _jobs[track.id] = task;
    try {
      await task;
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
          progress[track.id] = value;
          notifyListeners();
        },
      );
    } catch (error) {
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
  }

  Future<void> _removeUnlocked(String id) async {
    final entry = object(entries.remove(id));
    if (entry.isNotEmpty) {
      final file = File(p.join(directory.path, entry['file'] as String));
      if (await file.exists()) {
        await file.delete();
      }
    }
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
    for (final token in _tokens.values) {
      token.cancel();
    }
    await Future.wait(
      _jobs.values.map((job) => job.catchError((_) {})).toList(),
    );
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
