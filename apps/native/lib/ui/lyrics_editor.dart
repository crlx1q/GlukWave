import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/lyrics.dart';
import '../l10n/wave_localizations.dart';
import '../l10n/lyrics_strings.dart';
import 'widgets.dart';

class LyricsEditor extends StatefulWidget {
  final WaveController controller;
  final WaveTrack track;
  final String initialText;
  final bool Function() isCurrent;
  final Future<void> Function() onSaved;
  const LyricsEditor({
    super.key,
    required this.controller,
    required this.track,
    required this.initialText,
    required this.isCurrent,
    required this.onSaved,
  });
  @override
  State<LyricsEditor> createState() => _LyricsEditorState();
}

class _LyricsEditorState extends State<LyricsEditor> {
  WaveController get c => widget.controller;
  late final text = TextEditingController(text: widget.initialText),
      title = TextEditingController(text: widget.track.title),
      artist = TextEditingController(text: widget.track.artist);
  final url = TextEditingController();
  List<Json>? candidates;
  Json? selected, genius;
  String source = 'lrclib', error = '';
  bool busy = false, saving = false;
  int revision = 0;
  bool get current => mounted && widget.isCurrent();
  @override
  void dispose() {
    revision++;
    for (final editor in [text, title, artist, url]) {
      editor.dispose();
    }
    super.dispose();
  }

  String get base =>
      '/api/tracks/${Uri.encodeComponent(widget.track.id)}/lyrics';
  Future<void> search() async {
    if (!current) return;
    final run = ++revision;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await c.api.call(
        '$base/search',
        query: {'title': title.text, 'artist': artist.text},
      );
      if (current && revision == run) {
        setState(() => candidates = objects(result['candidates']));
      }
    } catch (failure) {
      if (current && revision == run) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (current && revision == run) setState(() => busy = false);
    }
  }

  Future<void> preview() async {
    if (!current) return;
    FocusScope.of(context).unfocus();
    final valid = geniusLyricsUrl(url.text);
    if (valid == null) {
      setState(() => error = lt(context, 'lyrics.geniusInvalid'));
      return;
    }
    final run = ++revision;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await c.api.call(
        '$base/genius/preview',
        method: 'POST',
        data: {'url': valid},
      );
      if (current && revision == run) {
        setState(() {
          genius = result;
          selected = null;
          text.text =
              result['raw'] as String? ??
              objects(
                result['lines'],
              ).map((line) => line['text'] ?? '').join('\n');
        });
      }
    } catch (failure) {
      if (current && revision == run) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (current && revision == run) setState(() => busy = false);
    }
  }

  Future<void> pickFile() async {
    if (!current) return;
    final run = ++revision;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'lrc'],
        withData: true,
      );
      if (!current || revision != run || result == null) return;
      final file = result.files.single;
      if (file.size > 200000) {
        setState(() => error = lt(context, 'lyrics.fileTooLarge'));
        return;
      }
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (current && revision == run && bytes != null) {
        setState(() {
          selected = null;
          genius = null;
          text.text = utf8
              .decode(bytes, allowMalformed: true)
              .replaceFirst('\uFEFF', '');
          error = '';
        });
      }
    } catch (failure) {
      if (current && revision == run) {
        setState(() => error = failure.toString());
      }
    }
  }

  Future<void> save() async {
    if (!current || busy || saving) return;
    final run = ++revision;
    setState(() {
      saving = true;
      error = '';
    });
    try {
      if (genius != null && text.text == genius!['raw']) {
        await c.api.call(
          '$base/genius',
          method: 'POST',
          data: {'url': genius!['sourceUrl']},
        );
      } else if (selected != null && text.text == selected!['raw']) {
        await c.api.call(
          '$base/lrclib',
          method: 'POST',
          data: {'providerId': selected!['providerId']},
        );
      } else {
        await c.api.call(base, method: 'PUT', data: {'text': text.text});
      }
      if (mounted && widget.isCurrent() && revision == run) {
        Navigator.pop(context);
        await widget.onSaved();
      }
    } catch (failure) {
      if (current && revision == run) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (current && revision == run) setState(() => saving = false);
    }
  }

  void choose(String value) {
    revision++;
    setState(() {
      source = value;
      busy = false;
      error = '';
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final valid = widget.isCurrent(), v = waveVisuals(context);
      final unchangedGenius = genius != null && text.text == genius!['raw'];
      return AlertDialog(
        title: Text(wt('native.da4b2995ca', context: context)),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in ['lrclib', 'genius'])
                      ChoiceChip(
                        label: Text(name == 'genius' ? 'Genius' : 'LRCLIB'),
                        selected: source == name,
                        onSelected: saving || !valid
                            ? null
                            : (_) => choose(name),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (!valid)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      lt(context, 'lyrics.scopeChanged'),
                      style: TextStyle(color: v.muted),
                    ),
                  ),
                if (source == 'lrclib') ...[
                  TextField(
                    controller: title,
                    enabled: valid && !saving,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: wt('lyrics.title', context: context),
                    ),
                  ),
                  TextField(
                    controller: artist,
                    enabled: valid && !saving,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: wt('lyrics.artist', context: context),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.search),
                      label: Text(wt('lyrics.search', context: context)),
                      onPressed: busy || saving || !valid ? null : search,
                    ),
                  ),
                  if (candidates != null && candidates!.isEmpty)
                    Text(wt('lyrics.none', context: context)),
                  if (candidates != null)
                    ...candidates!.map(
                      (candidate) => ListTile(
                        selected:
                            selected?['providerId'] == candidate['providerId'],
                        title: Text(candidate['title'] as String? ?? ''),
                        subtitle: Text(
                          '${candidate['artist']} · ${candidate['synchronized'] == true ? wt('lyrics.synced', context: context) : wt('lyrics.plain', context: context)}',
                        ),
                        onTap: saving || !valid
                            ? null
                            : () => setState(() {
                                selected = candidate;
                                genius = null;
                                text.text = candidate['raw'] as String? ?? '';
                              }),
                      ),
                    ),
                ] else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: v.surface,
                      border: Border.all(color: v.line),
                      borderRadius: BorderRadius.circular(v.corners(14)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('genius-url'),
                            controller: url,
                            enabled: valid && !saving,
                            keyboardType: TextInputType.url,
                            maxLength: 2000,
                            decoration: InputDecoration(
                              labelText: lt(context, 'lyrics.geniusUrl'),
                              hintText: 'https://genius.com/artist-song-lyrics',
                            ),
                            onChanged: (_) {
                              revision++;
                              setState(() {
                                busy = false;
                                error = '';
                              });
                            },
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const Key('genius-preview'),
                              icon: const Icon(Icons.download_rounded),
                              label: Text(
                                lt(
                                  context,
                                  busy
                                      ? 'lyrics.geniusLoading'
                                      : 'lyrics.geniusPreview',
                                ),
                              ),
                              onPressed: busy || saving || !valid
                                  ? null
                                  : preview,
                            ),
                          ),
                          Text(
                            lt(context, 'lyrics.geniusHelp'),
                            style: TextStyle(
                              color: v.muted,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error,
                      key: const Key('lyrics-source-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (unchangedGenius)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      lt(context, 'lyrics.geniusCredit'),
                      style: TextStyle(color: v.muted, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('lyrics-draft'),
                  controller: text,
                  enabled: valid && !saving,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 100000,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: wt('native.c157a9e867', context: context),
                    hintText: wt('native.59f2a68e7e', context: context),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(lt(context, 'lyrics.file')),
                    onPressed: valid && !saving && !busy ? pickFile : null,
                  ),
                ),
                Text(
                  selected != null && text.text == selected!['raw']
                      ? wt('lyrics.attribution', context: context)
                      : lt(context, 'lyrics.draftHelp'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              revision++;
              Navigator.pop(context);
            },
            child: Text(wt('native.0ec753be8d', context: context)),
          ),
          FilledButton(
            key: const Key('lyrics-save'),
            onPressed:
                busy ||
                    saving ||
                    !valid ||
                    text.text.trim().isEmpty &&
                        selected?['instrumental'] != true
                ? null
                : save,
            child: Text(
              saving
                  ? lt(context, 'lyrics.saving')
                  : wt('native.4864057d62', context: context),
            ),
          ),
        ],
      );
    },
  );
}
