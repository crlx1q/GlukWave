import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../core/controller.dart';
import '../core/home_layout.dart';
import '../core/models.dart';
import '../l10n/glukwave27_ui_strings.dart';
import '../l10n/home_canvas_strings.dart';
import 'refinement20_home.dart';
import 'parity_panels.dart' show PlaylistArtwork;
import 'widgets.dart';

/// The live home is the editor. Logical spans survive window/device changes;
/// draft movement never touches account settings until the user presses Done.
class NativeHomeCanvas extends StatefulWidget {
  final WaveController controller;
  final WidgetBuilder waveBuilder;
  final List<WaveTrack> recommendations;
  final bool recommendationsLoading;
  final String? recommendationsError;
  final VoidCallback onRetry, onLikes, onCreatePlaylist;
  final ValueChanged<Json> onPlaylist;
  final Widget? recommendationFooter;
  const NativeHomeCanvas({
    super.key,
    required this.controller,
    required this.waveBuilder,
    this.recommendations = const [],
    this.recommendationsLoading = false,
    this.recommendationsError,
    required this.onRetry,
    required this.onLikes,
    required this.onCreatePlaylist,
    required this.onPlaylist,
    this.recommendationFooter,
  });
  @override
  State<NativeHomeCanvas> createState() => _NativeHomeCanvasState();
}

class _NativeHomeCanvasState extends State<NativeHomeCanvas> {
  WaveController get c => widget.controller;
  final _toolbar = OverlayPortalController();
  final _focus = FocusNode(debugLabel: 'Home canvas');
  final _canvasKey = GlobalKey();
  final _keys = <String, GlobalKey>{};
  final _boundaries = <String, GlobalKey>{};
  final _snapshot = ValueNotifier<ui.Image?>(null);
  final _liveDrag = ValueNotifier<String?>(null);
  List<Json> _draft = [], _beforeDrag = [];
  String? _scope, _baseline, _dragging, _selected, _pendingMix;
  bool _editing = false, _saving = false, _remoteChanged = false;
  bool _resetDefault = false, _beforeDragDefault = false;
  String? _error;
  Offset? _pointer;
  Timer? _autoScroll;
  int _serial = 0;
  int _dragGeneration = 0;
  String get scope => '${c.api.server}|${c.user?.id}|${c.api.token}';
  String text(String key) => canvasText(context, key);
  List<Json> get current => resolveHomeCanvas(
    c.settings['homeLayout'],
    pins: objects(c.settings['homePins']),
    ownedPlaylists: c.playlists.map((p) => '${p['id']}').toSet(),
  );
  @override
  void initState() {
    super.initState();
    c.addListener(_accountChanged);
  }

  @override
  void didUpdateWidget(NativeHomeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_accountChanged);
      c.addListener(_accountChanged);
      _accountChanged();
    }
  }

  void _accountChanged() {
    if (!mounted || !_editing) return;
    if (_scope != scope) {
      _stopScroll();
      _liveDrag.value = null;
      _toolbar.hide();
      setState(() {
        _editing = false;
        _saving = false;
        _draft = [];
        _dragging = null;
        _error = null;
      });
    } else if (!_saving && jsonEncode(c.settings['homeLayout']) != _baseline) {
      setState(() => _remoteChanged = true);
    }
  }

  void _edit() {
    setState(() {
      _scope = scope;
      _baseline = jsonEncode(c.settings['homeLayout']);
      _draft = current.map(Json.of).toList();
      _editing = true;
      _resetDefault = false;
      _remoteChanged = false;
      _error = null;
      _selected = _draft.firstOrNull?['id'];
    });
    _toolbar.show();
    _focus.requestFocus();
  }

  void _cancel() {
    _stopScroll();
    _liveDrag.value = null;
    _toolbar.hide();
    setState(() {
      _editing = false;
      _dragging = null;
      _draft = [];
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving || _remoteChanged || _scope != scope) return;
    final account = scope, baseline = _baseline;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await c.updateSettings({
        'homeLayout': _resetDefault ? null : homeCanvasSettings(_draft),
      });
      if (!mounted || account != scope || baseline != _baseline) return;
      _toolbar.hide();
      setState(() {
        _editing = false;
        _saving = false;
        _dragging = null;
      });
    } catch (_) {
      if (mounted && account == scope) {
        setState(() {
          _saving = false;
          _error = text('savedError');
        });
      }
    }
  }

  void _move(String id, int to) {
    final from = _draft.indexWhere((w) => w['id'] == id);
    if (from < 0 || _saving || to == from || to < 0 || to >= _draft.length) {
      return;
    }
    setState(() {
      final item = _draft.removeAt(from);
      _draft.insert(to, item);
      _selected = id;
      _resetDefault = false;
    });
  }

  void _startDrag(String id) {
    if (!_editing || _saving) return;
    _beforeDrag = _draft.map(Json.of).toList();
    _beforeDragDefault = _resetDefault;
    final oldImage = _snapshot.value;
    _snapshot.value = null;
    if (oldImage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => oldImage.dispose());
    }
    setState(() {
      _dragging = id;
      _selected = id;
    });
    _liveDrag.value = id;
    _capture(id, ++_dragGeneration);
    HapticFeedback.selectionClick();
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _scrollAtEdge(),
    );
  }

  Future<void> _capture(String id, int generation) async {
    final boundary = _boundaries[id]?.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.debugNeedsPaint) return;
    try {
      final image = await boundary.toImage(pixelRatio: 1);
      if (!mounted || _liveDrag.value != id || generation != _dragGeneration) {
        image.dispose();
        return;
      }
      _snapshot.value?.dispose();
      _snapshot.value = image;
    } catch (_) {
      /* A lightweight title/cover proxy remains available. */
    }
  }

  void _stopScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointer = null;
  }

  void _endDrag(bool accepted) {
    if (!mounted || _dragging == null) return;
    _stopScroll();
    _liveDrag.value = null;
    setState(() {
      if (!accepted) {
        _draft = _beforeDrag.map(Json.of).toList();
        _resetDefault = _beforeDragDefault;
      }
      _dragging = null;
    });
  }

  void _dragMove(Offset point) {
    _pointer = point;
    if (_dragging == null) return;
    String? target;
    double distance = double.infinity;
    for (final item in _draft) {
      final box = _keys[item['id']]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final dx = point.dx.clamp(rect.left, rect.right) - point.dx;
      final dy = point.dy.clamp(rect.top, rect.bottom) - point.dy;
      final d = dx * dx + dy * dy;
      if (d < distance) {
        target = item['id'];
        distance = d;
      }
    }
    if (target != null && target != _dragging && distance < 16000) {
      _move(_dragging!, _draft.indexWhere((w) => w['id'] == target));
    }
  }

  void _scrollAtEdge() {
    if (!mounted || _pointer == null || _dragging == null) return;
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll == null || !scroll.hasContentDimensions) return;
    final h = MediaQuery.sizeOf(context).height, y = _pointer!.dy;
    final delta = y < 150
        ? -math.min(20.0, (150 - y) / 4)
        : y > h - 190
        ? math.min(20.0, (y - h + 190) / 4)
        : 0.0;
    if (delta == 0) return;
    final next = (scroll.pixels + delta).clamp(
      scroll.minScrollExtent,
      scroll.maxScrollExtent,
    );
    if (next != scroll.pixels) {
      scroll.jumpTo(next);
      _dragMove(_pointer!);
    }
  }

  @override
  void dispose() {
    _stopScroll();
    _focus.dispose();
    c.removeListener(_accountChanged);
    _snapshot.value?.dispose();
    _snapshot.dispose();
    _liveDrag.dispose();
    super.dispose();
  }

  String _title(Json item) {
    if (item['type'] == 'mix') return '${item['genre']}';
    if (item['type'] == 'playlist') {
      return c.playlists
              .where((p) => p['id'] == item['playlistId'])
              .firstOrNull?['name']
              ?.toString() ??
          text('playlist');
    }
    return text('${item['type']}');
  }

  KeyEventResult _keyboard(FocusNode node, KeyEvent event) {
    if (!_editing || event is! KeyDownEvent || _saving) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_dragging != null) {
        _endDrag(false);
      } else {
        _cancel();
      }
      return KeyEventResult.handled;
    }
    final i = _draft.indexWhere((w) => w['id'] == _selected);
    if (i >= 0 && HardwareKeyboard.instance.isAltPressed) {
      if ({
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowLeft,
      }.contains(event.logicalKey)) {
        _move(_selected!, i - 1);
        return KeyEventResult.handled;
      }
      if ({
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowRight,
      }.contains(event.logicalKey)) {
        _move(_selected!, i + 1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), items = _editing ? _draft : current;
    return OverlayPortal(
      controller: _toolbar,
      overlayChildBuilder: (_) => Positioned(
        left: 12,
        right: 12,
        bottom:
            MediaQuery.paddingOf(context).bottom +
            (MediaQuery.sizeOf(context).width < 700 ? 160 : 130),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _editToolbar(),
          ),
        ),
      ),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _keyboard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_editing)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('home-canvas-edit'),
                  onPressed: _edit,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(
                    text('edit'),
                    style: TextStyle(fontSize: 12, color: v.muted),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text('editing'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      text('hint'),
                      style: TextStyle(
                        color: v.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    if (_remoteChanged || _error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _remoteChanged ? text('changed') : _error!,
                          key: const Key('home-canvas-error'),
                          style: TextStyle(color: v.accent, height: 1.5),
                        ),
                      ),
                  ],
                ),
              ),
            CustomPaint(
              key: _canvasKey,
              painter: _editing
                  ? _CanvasDots(v.muted.withValues(alpha: .14))
                  : null,
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final gap = bounds.maxWidth < 400 ? 12.0 : 16.0;
                  return DragTarget<String>(
                    onWillAcceptWithDetails: (data) =>
                        _editing && data.data == _dragging,
                    onAcceptWithDetails: (_) => _endDrag(true),
                    builder: (_, candidates, rejects) => Wrap(
                      spacing: gap,
                      runSpacing: _editing ? 18 : 28,
                      children: [
                        for (final item in items)
                          _CanvasReflow(
                            key: ValueKey('motion-${item['id']}'),
                            reduced:
                                v.reducedMotion ||
                                MediaQuery.disableAnimationsOf(context),
                            origin: () =>
                                (_canvasKey.currentContext?.findRenderObject()
                                        as RenderBox?)
                                    ?.localToGlobal(Offset.zero) ??
                                Offset.zero,
                            child: _cell(
                              item,
                              homeCanvasWidth(
                                bounds.maxWidth,
                                '${item['size']}',
                                gap: gap,
                              ),
                            ),
                          ),
                        if (_editing && items.isEmpty)
                          SizedBox(
                            width: bounds.maxWidth,
                            height: 180,
                            child: Center(
                              child: TextButton.icon(
                                onPressed: _gallery,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(text('add')),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_editing) const SizedBox(height: 200),
          ],
        ),
      ),
    );
  }

  Widget _editToolbar() {
    final v = waveVisuals(context);
    return Material(
      elevation: 16,
      color: v.surface,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: .35),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: v.line),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            TextButton.icon(
              key: const Key('home-canvas-add'),
              onPressed: _saving || _draft.length >= 20 ? null : _gallery,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(text('add')),
            ),
            TextButton(
              key: const Key('home-canvas-reset'),
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _draft = defaultHomeCanvas(
                        objects(c.settings['homePins']),
                      );
                      _resetDefault = true;
                      _selected = 'wave';
                    }),
              child: Text(text('reset')),
            ),
            TextButton(
              key: const Key('home-canvas-cancel'),
              onPressed: _saving ? null : _cancel,
              child: Text(text('cancel')),
            ),
            FilledButton(
              key: const Key('home-canvas-save'),
              onPressed: _saving || _remoteChanged ? null : _save,
              child: Text(_saving ? '…' : text('done')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(Json item, double width) {
    final id = '${item['id']}', v = waveVisuals(context);
    _keys.putIfAbsent(id, GlobalKey.new);
    _boundaries.putIfAbsent(id, GlobalKey.new);
    final active = _dragging == id;
    final frame = Container(
      key: _keys[id],
      decoration: BoxDecoration(
        color: _editing ? v.surface.withValues(alpha: .55) : Colors.transparent,
        border: _editing
            ? Border.all(
                color: _selected == id
                    ? v.accent.withValues(alpha: .75)
                    : v.line,
                width: _selected == id ? 1.2 : 1,
              )
            : null,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: _editing
          ? const EdgeInsets.fromLTRB(12, 6, 12, 14)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing) _itemChrome(item),
          IgnorePointer(
            ignoring: _editing,
            child: RepaintBoundary(key: _boundaries[id], child: _content(item)),
          ),
        ],
      ),
    );
    if (!_editing) {
      return SizedBox(key: ValueKey('canvas-$id'), width: width, child: frame);
    }
    final feedback = ValueListenableBuilder<String?>(
      valueListenable: _liveDrag,
      builder: (_, live, __) {
        if (live != id) return const SizedBox.shrink();
        return SizedBox(
          width: width,
          child: Material(
            color: v.surface,
            elevation: 24,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              key: const Key('home-canvas-lifted'),
              decoration: BoxDecoration(
                border: Border.all(color: v.accent),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(14),
              child: ValueListenableBuilder<ui.Image?>(
                valueListenable: _snapshot,
                builder: (_, image, __) => image == null
                    ? Row(
                        children: [
                          Icon(Icons.drag_indicator_rounded, color: v.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _title(item),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 380),
                        child: ClipRect(
                          child: RawImage(
                            image: image,
                            fit: BoxFit.contain,
                            alignment: Alignment.topLeft,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
    final child = AnimatedOpacity(
      duration: v.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      opacity: active ? .18 : 1,
      child: frame,
    );
    return SizedBox(
      key: ValueKey('canvas-$id'),
      width: width,
      child: Semantics(
        label: '${_title(item)}. ${text('move')}',
        child: DragTarget<String>(
          onWillAcceptWithDetails: (data) => data.data == _dragging,
          onAcceptWithDetails: (_) => _endDrag(true),
          builder: (_, __, ___) => Listener(
            onPointerDown: (_) {
              if (_selected != id) setState(() => _selected = id);
            },
            child: LongPressDraggable<String>(
              data: id,
              maxSimultaneousDrags: _saving || _dragging != null ? 0 : 1,
              delay: const Duration(milliseconds: 350),
              hapticFeedbackOnStart: false,
              dragAnchorStrategy: (_, __, ___) => Offset(width / 2, 28),
              feedback: feedback,
              onDragStarted: () => _startDrag(id),
              onDragUpdate: (d) => _dragMove(d.globalPosition),
              onDragEnd: (d) => _endDrag(d.wasAccepted),
              child: _HandleDragRegion(
                enabled: !_saving && _dragging == null,
                data: id,
                feedback: feedback,
                onStart: () => _startDrag(id),
                onMove: _dragMove,
                onEnd: _endDrag,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemChrome(Json item) {
    final id = '${item['id']}',
        index = _draft.indexOf(item),
        v = waveVisuals(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            key: Key('home-canvas-grab-$id'),
            width: 32,
            height: 38,
            child: Icon(Icons.drag_indicator_rounded, size: 19, color: v.muted),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, bounds) => bounds.maxWidth < 58
                  ? Tooltip(
                      message: text('${item['size']}'),
                      child: Icon(
                        Icons.grid_view_rounded,
                        size: 13,
                        color: v.muted,
                      ),
                    )
                  : Text(
                      text('${item['size']}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: v.muted, fontSize: 10),
                    ),
            ),
          ),
          PopupMenuButton<String>(
            key: Key('home-canvas-options-$id'),
            tooltip: text('options'),
            padding: EdgeInsets.zero,
            iconSize: 18,
            onSelected: (value) {
              if (_saving) return;
              _resetDefault = false;
              if (value == 'remove') {
                setState(() => _draft.removeWhere((w) => w['id'] == id));
              } else if (value == 'back') {
                _move(id, index - 1);
              } else if (value == 'forward') {
                _move(id, index + 1);
              } else {
                final parts = value.split(':');
                setState(() => item[parts[0]] = parts[1]);
              }
            },
            itemBuilder: (_) => [
              for (final size in homeCanvasSizes)
                CheckedPopupMenuItem(
                  value: 'size:$size',
                  checked: item['size'] == size,
                  child: Text(text(size)),
                ),
              const PopupMenuDivider(),
              for (final view in homeCanvasViews)
                CheckedPopupMenuItem(
                  value: 'view:$view',
                  checked: item['view'] == view,
                  child: Text(text(view)),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'back',
                enabled: index > 0,
                child: Text(text('back')),
              ),
              PopupMenuItem(
                value: 'forward',
                enabled: index < _draft.length - 1,
                child: Text(text('forward')),
              ),
              PopupMenuItem(value: 'remove', child: Text(text('remove'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heading(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (action != null) action,
      ],
    ),
  );

  Widget _content(Json item) {
    final type = item['type'], view = '${item['view']}', title = _title(item);
    if (type == 'wave') {
      if (view == 'cards') return widget.waveBuilder(context);
      return _destination(
        item,
        title,
        Icons.waves_rounded,
        onTap: c.online
            ? () async {
                try {
                  await c.startWave();
                } catch (e) {
                  c.tell(e.toString());
                }
              }
            : null,
        subtitle: c.online ? wave27Text(context, 'daily') : text('offline'),
      );
    }
    if (type == 'playlists') return _playlists(item);
    if (type == 'likes' || type == 'playlist' || type == 'mix') {
      final list = type == 'playlist'
          ? c.playlists.where((p) => p['id'] == item['playlistId']).firstOrNull
          : null;
      return _destination(
        item,
        title,
        type == 'likes'
            ? Icons.favorite_border_rounded
            : type == 'mix'
            ? Icons.radio_rounded
            : Icons.queue_music_rounded,
        playlist: list,
        subtitle: type == 'likes'
            ? '${c.likedIds.length}'
            : type == 'mix'
            ? text('mix')
            : list == null
            ? text('unavailable')
            : '${(list['trackIds'] as List?)?.length ?? 0}',
        onTap: type == 'playlist' && list == null
            ? null
            : () {
                if (type == 'likes') {
                  widget.onLikes();
                } else if (type == 'playlist' && list != null) {
                  widget.onPlaylist(list);
                } else if (type == 'mix') {
                  _playMix(item);
                }
              },
      );
    }
    if (type == 'daily') return _daily(item);
    if (type == 'discovery' || type == 'popular') {
      return NativeDiscoveryShelf(
        key: ValueKey('$type:${c.user?.id}:${c.api.server}'),
        controller: c,
        mode: type,
        view: view,
        embedded: true,
      );
    }
    final recent = c.history
        .map((e) => c.track(e['trackId'] as String?))
        .whereType<WaveTrack>()
        .take(8)
        .toList();
    final tracks = type == 'recommendations'
        ? widget.recommendations
        : recent.isNotEmpty
        ? recent
        : c.tracks.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(title),
        if (type == 'recommendations' &&
            widget.recommendationsLoading &&
            tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (tracks.isEmpty)
          _empty(
            action:
                type == 'recommendations' && widget.recommendationsError != null
                ? widget.onRetry
                : null,
          )
        else
          NativeCanvasTracks(controller: c, tracks: tracks, view: view),
        if (type == 'recommendations' &&
            view == 'cards' &&
            item['size'] != 'small' &&
            widget.recommendationFooter != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: widget.recommendationFooter!,
          ),
      ],
    );
  }

  Widget _empty({VoidCallback? action}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.online ? text('empty') : text('offline'),
          style: TextStyle(
            color: waveVisuals(context).muted,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        if (action != null)
          TextButton(onPressed: action, child: Text(text('retry'))),
      ],
    ),
  );
  Widget _playlists(Json item) {
    final v = waveVisuals(context), view = item['view'], lists = c.playlists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          text('playlists'),
          action: IconButton(
            key: const Key('home-canvas-create-playlist'),
            onPressed: widget.onCreatePlaylist,
            tooltip: text('create'),
            icon: const Icon(Icons.add_rounded, size: 20),
          ),
        ),
        if (lists.isEmpty)
          _empty(action: widget.onCreatePlaylist)
        else if (view == 'cards')
          LayoutBuilder(
            builder: (_, bounds) {
              final columns = math.max(1, (bounds.maxWidth / 155).floor());
              final size = (bounds.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 18,
                children: [
                  for (final playlist in lists.take(
                    item['size'] == 'small' ? 2 : 8,
                  ))
                    SizedBox(
                      width: size,
                      child: InkWell(
                        onTap: () => widget.onPlaylist(playlist),
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PlaylistArtwork(
                              controller: c,
                              playlist: playlist,
                              size: size,
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '${playlist['name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(playlist['trackIds'] as List?)?.length ?? 0}',
                              style: TextStyle(color: v.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          )
        else
          Column(
            children: [
              for (final list in lists.take(view == 'compact' ? 3 : 6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => widget.onPlaylist(list),
                    child: Row(
                      children: [
                        if (view != 'compact') ...[
                          PlaylistArtwork(
                            controller: c,
                            playlist: list,
                            size: 42,
                          ),
                          const SizedBox(width: 11),
                        ] else ...[
                          Icon(
                            Icons.queue_music_rounded,
                            color: v.accent,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            '${list['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(list['trackIds'] as List?)?.length ?? 0}',
                          style: TextStyle(color: v.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _destination(
    Json item,
    String title,
    IconData icon, {
    String? subtitle,
    Json? playlist,
    VoidCallback? onTap,
  }) {
    final v = waveVisuals(context),
        view = item['view'],
        compact = view == 'compact';
    Widget image(double size) => playlist != null
        ? PlaylistArtwork(controller: c, playlist: playlist, size: size)
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: v.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: v.accent, size: size * .44),
          );
    return Material(
      color: v.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('home-canvas-open-${item['id']}'),
        onTap: _pendingMix == null ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 16),
          child: view == 'cards'
              ? LayoutBuilder(
                  builder: (_, bounds) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      image(math.min(bounds.maxWidth, 148)),
                      const SizedBox(height: 15),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle ?? '',
                        style: TextStyle(color: v.muted, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (_, bounds) {
                    if (compact && bounds.maxWidth < 150) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          image(32),
                          const SizedBox(height: 11),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: v.muted),
                            ),
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        image(compact ? 36 : 56),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: compact ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  _pendingMix == item['id'] ? '…' : subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: v.muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!compact)
                          Icon(
                            Icons.north_east_rounded,
                            size: 17,
                            color: v.muted,
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _playMix(Json item, {String? daily}) async {
    if (_pendingMix != null) return;
    final account = scope;
    setState(() => _pendingMix = '${item['id']}');
    try {
      final now = DateTime.now(),
          data = await c.api.cachedCall(
            '/api/recommendations',
            query: {
              if (daily != null)
                'mix': daily
              else ...{
                'genre': item['genre'],
                'mood': item['mood'] ?? 'personal',
              },
              'day':
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
              'limit': 30,
            },
          );
      if (!mounted || account != scope) return;
      final tracks = objects(data['tracks']).map(WaveTrack.new).toList();
      if (tracks.isEmpty) {
        c.tell(text('empty'));
      } else {
        await c.play(tracks.first, list: tracks);
      }
    } catch (error) {
      if (mounted && account == scope) c.tell(error.toString());
    } finally {
      if (mounted && account == scope) setState(() => _pendingMix = null);
    }
  }

  Widget _daily(Json item) {
    final v = waveVisuals(context), view = item['view'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(text('daily')),
        LayoutBuilder(
          builder: (_, bounds) {
            final columns = view == 'list' || bounds.maxWidth < 230
                ? 1
                : bounds.maxWidth < 600
                ? 2
                : 4;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final row in const [
                  ('morning', Icons.wb_sunny_outlined),
                  ('focus', Icons.adjust_rounded),
                  ('evening', Icons.nightlight_outlined),
                  ('discovery', Icons.auto_awesome_outlined),
                ])
                  SizedBox(
                    width: (bounds.maxWidth - (columns - 1) * 10) / columns,
                    child: Material(
                      color: v.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => _playMix(item, daily: row.$1),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: EdgeInsets.all(view == 'compact' ? 10 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(row.$2, color: v.accent, size: 22),
                              const SizedBox(height: 12),
                              Text(
                                wave27Text(context, row.$1),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _gallery() async {
    var genre = '';
    final account = scope;
    String? playlist = c.playlists.firstOrNull?['id']?.toString();
    final present = _draft.map((w) => w['type']).toSet();
    final result = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) {
          final v = waveVisuals(sheet);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                22,
                8,
                22,
                MediaQuery.viewInsetsOf(sheet).bottom + 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheet).height * .72,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        text('add'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 23,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final type in [
                        'wave',
                        'playlists',
                        'recent',
                        'recommendations',
                        'discovery',
                        'popular',
                        'daily',
                        'likes',
                      ])
                        if (!present.contains(type))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            key: Key('home-canvas-gallery-$type'),
                            title: Text(
                              text(type),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: Icon(Icons.add_rounded, color: v.accent),
                            onTap: () => Navigator.pop(sheet, {
                              'type': type,
                              'size': type == 'likes' ? 'small' : 'large',
                              'view': type == 'likes' ? 'compact' : 'cards',
                            }),
                          ),
                      if (c.playlists.isNotEmpty) ...[
                        const Divider(height: 28),
                        Text(
                          text('playlist'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: playlist,
                          isExpanded: true,
                          items: [
                            for (final p in c.playlists)
                              DropdownMenuItem(
                                value: '${p['id']}',
                                child: Text(
                                  '${p['name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => update(() => playlist = value),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => Navigator.pop(sheet, {
                              'type': 'playlist',
                              'playlistId': playlist,
                              'size': 'small',
                              'view': 'compact',
                            }),
                            icon: const Icon(Icons.add_rounded),
                            label: Text(text('add')),
                          ),
                        ),
                      ],
                      const Divider(height: 28),
                      Text(
                        text('mix'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('home-canvas-genre'),
                        maxLength: 40,
                        onChanged: (value) => update(() => genre = value),
                        decoration: InputDecoration(hintText: text('genre')),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const Key('home-canvas-add-mix'),
                          onPressed: genre.trim().isEmpty
                              ? null
                              : () => Navigator.pop(sheet, {
                                  'type': 'mix',
                                  'genre': genre.trim(),
                                  'mood': 'personal',
                                  'size': 'small',
                                  'view': 'compact',
                                }),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(text('add')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted ||
        !_editing ||
        account != scope ||
        result == null ||
        _draft.length >= 20) {
      return;
    }
    setState(() {
      final id = 'native-${DateTime.now().millisecondsSinceEpoch}-${_serial++}';
      _draft.add({'id': id, ...result});
      _resetDefault = false;
      _selected = id;
    });
  }
}

/// Only the visible grab region starts an immediate mouse drag. Touch outside
/// it keeps ordinary scrolling until the parent's delayed pickup wins.
class _HandleDragRegion extends StatelessWidget {
  final Widget child, feedback;
  final bool enabled;
  final String data;
  final VoidCallback onStart;
  final ValueChanged<Offset> onMove;
  final ValueChanged<bool> onEnd;
  const _HandleDragRegion({
    required this.child,
    required this.feedback,
    required this.enabled,
    required this.data,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(
        left: 12,
        top: 6,
        width: 32,
        height: 38,
        child: _MouseDraggable<String>(
          data: data,
          maxSimultaneousDrags: enabled ? 1 : 0,
          allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
          feedback: feedback,
          dragAnchorStrategy: (_, __, ___) => const Offset(24, 24),
          onDragStarted: onStart,
          onDragUpdate: (d) => onMove(d.globalPosition),
          onDragEnd: (d) => onEnd(d.wasAccepted),
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Semantics(
              label: canvasText(context, 'move'),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        ),
      ),
    ],
  );
}

class _MouseDraggable<T extends Object> extends Draggable<T> {
  const _MouseDraggable({
    required super.child,
    required super.feedback,
    required super.data,
    super.maxSimultaneousDrags,
    super.allowedButtonsFilter,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
  });
  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {PointerDeviceKind.mouse},
    allowedButtonsFilter: allowedButtonsFilter,
  )..onStart = onStart;
}

class _CanvasDots extends CustomPainter {
  final Color color;
  _CanvasDots(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double x = 6; x < size.width; x += 20) {
      for (double y = 6; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), .7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasDots oldDelegate) => color != oldDelegate.color;
}

/// FLIP-style movement keeps a picked-up card's neighbours from teleporting.
/// The measured boundary excludes its child transform and outer scroll offset.
class _CanvasReflow extends StatefulWidget {
  final Widget child;
  final bool reduced;
  final Offset Function() origin;
  const _CanvasReflow({
    super.key,
    required this.child,
    required this.reduced,
    required this.origin,
  });
  @override
  State<_CanvasReflow> createState() => _CanvasReflowState();
}

class _CanvasReflowState extends State<_CanvasReflow>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 230),
  );
  Offset? last;
  Offset delta = Offset.zero;
  void measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final next = box.localToGlobal(Offset.zero) - widget.origin();
      if (last != null && next != last && !widget.reduced) {
        delta = last! - next;
        animation.forward(from: 0);
      }
      last = next;
    });
  }

  @override
  void initState() {
    super.initState();
    measure();
  }

  @override
  void didUpdateWidget(_CanvasReflow oldWidget) {
    super.didUpdateWidget(oldWidget);
    measure();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: animation,
      builder: (_, child) => Transform.translate(
        offset: widget.reduced
            ? Offset.zero
            : delta * (1 - Curves.easeOutCubic.transform(animation.value)),
        child: child,
      ),
      child: widget.child,
    ),
  );
}

/// Shared cover/list/compact content used by live discovery and local shelves.
class NativeCanvasTracks extends StatelessWidget {
  final WaveController controller;
  final List<WaveTrack> tracks;
  final String view;
  const NativeCanvasTracks({
    super.key,
    required this.controller,
    required this.tracks,
    this.view = 'cards',
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    void play(WaveTrack track) async {
      try {
        await controller.play(track, list: tracks);
      } catch (error) {
        controller.tell(error.toString());
      }
    }

    if (view != 'cards') {
      return Column(
        children: [
          for (final track in tracks.take(view == 'compact' ? 3 : 5))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: InkWell(
                onTap: () => play(track),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      if (view == 'list') ...[
                        Artwork(
                          controller: controller,
                          url: track.artwork,
                          size: 42,
                          radius: 9,
                        ),
                        const SizedBox(width: 11),
                      ] else ...[
                        Icon(
                          Icons.play_arrow_rounded,
                          color: v.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: v.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (_, bounds) {
        final size = math.min(
          bounds.maxWidth,
          bounds.maxWidth < 230 ? 116.0 : 148.0,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final track in tracks.take(8))
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: size,
                    child: InkWell(
                      onTap: () => play(track),
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Artwork(
                            controller: controller,
                            url: track.artwork,
                            size: size,
                            radius: 12,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: v.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
