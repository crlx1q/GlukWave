import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/glukwave27_ui_strings.dart';
import 'top_notice.dart';

/// A user preference only: saved tracks and playlists are not changed.
Future<void> excludeRecommendation(
  BuildContext context,
  WaveController c,
  WaveTrack track, {
  required bool artist,
}) async {
  final account = c.user?.id, origin = c.api.server;
  if (account == null || !c.online) return;
  final hidden = wave27Text(context, artist ? 'hiddenArtist' : 'hiddenTrack'),
      undo = wave27Text(context, 'undo'),
      restored = wave27Text(context, 'restored');
  try {
    await c.api.call(
      '/api/recommendations/exclude',
      method: 'POST',
      data: {'trackId': track.id, 'artist': artist, 'remove': false},
    );
  } catch (error) {
    if (account == c.user?.id) c.tell(error.toString());
    return;
  }
  if (!context.mounted || account != c.user?.id || origin != c.api.server) {
    return;
  }
  late OverlayEntry entry;
  var removed = false;
  void close() {
    if (removed) return;
    removed = true;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (_) => _RecommendationUndo(
      controller: c,
      account: account,
      origin: origin,
      text: hidden,
      undoLabel: undo,
      onClose: close,
      onUndo: () async {
        await c.api.call(
          '/api/recommendations/exclude',
          method: 'POST',
          data: {'trackId': track.id, 'artist': artist, 'remove': true},
        );
        if (account == c.user?.id && origin == c.api.server) c.tell(restored);
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
}

class _RecommendationUndo extends StatefulWidget {
  final WaveController controller;
  final String account, origin, text, undoLabel;
  final VoidCallback onClose;
  final Future<void> Function() onUndo;
  const _RecommendationUndo({
    required this.controller,
    required this.account,
    required this.origin,
    required this.text,
    required this.undoLabel,
    required this.onClose,
    required this.onUndo,
  });
  @override
  State<_RecommendationUndo> createState() => _RecommendationUndoState();
}

class _RecommendationUndoState extends State<_RecommendationUndo> {
  Timer? timer;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(scope);
    timer = Timer(const Duration(seconds: 12), widget.onClose);
  }

  void scope() {
    if (widget.account != widget.controller.user?.id ||
        widget.origin != widget.controller.api.server) {
      widget.onClose();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.controller.removeListener(scope);
    super.dispose();
  }

  Future<void> undo() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.onUndo();
      if (mounted) widget.onClose();
    } catch (error) {
      if (mounted) {
        setState(() => busy = false);
        widget.controller.tell(error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) => WaveTopNotice(
    key: const Key('recommendation-undo-notice'),
    text: widget.text,
    onClose: widget.onClose,
    actionLabel: widget.undoLabel,
    onAction: busy ? null : () => unawaited(undo()),
  );
}
