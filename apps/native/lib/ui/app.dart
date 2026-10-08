import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/controller.dart';
import '../core/appearance.dart';
import '../core/models.dart';
import 'equalizer_panel.dart';
import '../services/desktop.dart';
import 'widgets.dart';
import 'player.dart';
import 'appearance_panel.dart';
import 'auth_visuals.dart';
import 'auth_page.dart';
export 'auth_page.dart' show AuthPage;
import 'desktop_player.dart';
import 'lofi.dart';
import '../l10n/wave_localizations.dart';

enum WavePage {
  home,
  library,
  search,
  liked,
  rooms,
  sources,
  downloads,
  devices,
  profile,
  settings,
  admin,
}

List<String> get pageLabels => [
  wt('native.ffddd31c12'),
  wt('native.27925da08c'),
  wt('native.6433b522a1'),
  wt('native.d3aa3fa13d'),
  wt('native.200ba6b661'),
  wt('native.5384db72a4'),
  wt('native.212ccf5938'),
  wt('native.7ab03d602e'),
  wt('native.eb0b9b0d90'),
  wt('native.7f17c7c62a'),
  wt('native.5a214bdfe9'),
];
const pageIcons = [
  Icons.home_outlined,
  Icons.library_music_outlined,
  Icons.search_rounded,
  Icons.favorite_border_rounded,
  Icons.spatial_audio_off_outlined,
  Icons.hub_outlined,
  Icons.download_for_offline_outlined,
  Icons.devices_rounded,
  Icons.person_outline_rounded,
  Icons.tune_rounded,
  Icons.terminal_rounded,
];

class GlukWaveApp extends StatefulWidget {
  final WaveController controller;
  const GlukWaveApp({super.key, required this.controller});
  @override
  State<GlukWaveApp> createState() => _GlukWaveAppState();
}

class _GlukWaveAppState extends State<GlukWaveApp> with WidgetsBindingObserver {
  final messenger = GlobalKey<ScaffoldMessengerState>();
  int _notice = 0;
  WaveCustomization? _customization;
  ThemeData? _light, _dark;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    unawaited(widget.controller.systemLocaleChanged());
  }

  void _changed() {
    final c = widget.controller;
    if (c.noticeRevision == _notice || c.notice == null) return;
    _notice = c.noticeRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messenger.currentState?.hideCurrentSnackBar();
      messenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(c.notice!),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    timeDilation = 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, child) {
      final c = widget.controller, customization = c.customization;
      if (!identical(_customization, customization)) {
        _customization = customization;
        _light = buildWaveTheme(customization, Brightness.light);
        _dark = buildWaveTheme(customization, Brightness.dark);
        // Flutter uses this clock for its transitions and animated GIF frames.
        // A single clock keeps the logo, wave and controls at the same speed.
        timeDilation = 1 / customization.appearance.speed;
      }
      return MaterialApp(
        title: 'GlukWave',
        locale: Locale(c.resolvedLanguage),
        supportedLocales: WaveStrings.supportedLocales,
        localizationsDelegates: WaveStrings.delegates,
        theme: _light,
        darkTheme: _dark,
        themeMode: switch (customization.theme) {
          'dark' || 'amoled' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        },
        themeAnimationDuration: customization.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messenger,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) ||
                customization.reducedMotion,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            if (c.loading && c.user == null) {
              return const WaveStartupPage();
            }
            return c.loggedIn
                ? WaveShell(controller: c)
                : AuthPage(
                    controller: c,
                    onQrLogin: showQrLogin,
                    onServerDebug: kDebugMode
                        ? () => editServer(context, c)
                        : null,
                  );
          },
        ),
      );
    },
  );
}

Future<void> run(WaveController c, Future<dynamic> Function() action) async {
  try {
    await action();
  } catch (error) {
    c.tell(error.toString());
  }
}

Future<String?> askText(
  BuildContext context,
  String title,
  String label, {
  String value = '',
  bool multiline = false,
}) async {
  final text = TextEditingController(text: value);
  final result = await showWaveDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: text,
          autofocus: true,
          maxLines: multiline ? 6 : 1,
          maxLength: multiline ? 16000 : 200,
          decoration: InputDecoration(labelText: label),
          onSubmitted: multiline ? null : (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(wt('native.0ec753be8d', context: context)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, text.text.trim()),
          child: Text(wt('native.398c7d4f7b', context: context)),
        ),
      ],
    ),
  );
  text.dispose();
  return result?.trim().isEmpty == true ? null : result;
}

Future<void> editServer(BuildContext context, WaveController c) async {
  final value = await askText(
    context,
    wt('native.c6f95cad29', context: context),
    wt('native.8db46ea789', context: context),
    value: c.api.server,
  );
  if (value != null) await run(c, () => c.setServer(value));
}

class WaveShell extends StatefulWidget {
  final WaveController controller;
  const WaveShell({super.key, required this.controller});
  @override
  State<WaveShell> createState() => _WaveShellState();
}

class _WaveShellState extends State<WaveShell>
    with SingleTickerProviderStateMixin {
  WaveController get c => widget.controller;
  WavePage page = WavePage.home;
  String filter = 'all', source = 'all';
  Json? selectedPlaylist;
  final search = TextEditingController(), chat = TextEditingController();
  Timer? _searchTimer;
  bool searching = false;
  late final playerReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  final miniArtwork = GlobalKey(), fullArtwork = GlobalKey();
  bool playerVisible = false;
  WaveTrack? previewTrack;
  Rect? coverOrigin, coverDestination;
  double dragOrigin = 0;
  int playerTransition = 0;
  int searchRequest = 0;
  String settingsSection = 'account';
  @override
  void initState() {
    super.initState();
    // Compact desktop modes do not otherwise touch the full player animation.
    // Create its ticker while this State is alive, before dispose can run.
    playerReveal;
  }

  @override
  void dispose() {
    search.dispose();
    chat.dispose();
    _searchTimer?.cancel();
    playerReveal.dispose();
    super.dispose();
  }

  void navigate(WavePage value) {
    setState(() {
      page = value;
      if (value != WavePage.library) selectedPlaylist = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (c.desktop.mini || c.desktop.quick) {
      return DesktopCompactPlayer(controller: c, quick: c.desktop.quick);
    }
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final shell = Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (desktop) sidebar(),
            Expanded(
              child: Column(
                children: [
                  topbar(desktop),
                  if (c.error != null)
                    Material(
                      color: waveVisuals(context).accentSoft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                        child: Row(
                          children: [
                            Icon(
                              c.online
                                  ? Icons.info_outline
                                  : Icons.wifi_off_rounded,
                              size: 17,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                c.online
                                    ? c.error!
                                    : wt(
                                        'native.91cea4784a',
                                        values: {'p0': (c.error)},
                                        context: context,
                                      ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton(
                              onPressed: () => run(c, c.refresh),
                              child: Text(
                                wt('native.9e506acb19', context: context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (c.loading)
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: waveVisuals(context).accent,
                      backgroundColor: waveVisuals(context).background,
                    ),
                  Expanded(
                    child: page == WavePage.settings
                        ? Padding(
                            padding: EdgeInsets.fromLTRB(
                              desktop ? 32 : 20,
                              20,
                              desktop ? 32 : 20,
                              12,
                            ),
                            child: settingsPage(),
                          )
                        : AnimatedSwitcher(
                            duration: Duration(
                              milliseconds: c.settings['reducedMotion'] == true
                                  ? 0
                                  : 220,
                            ),
                            child: SingleChildScrollView(
                              key: ValueKey('$page:${selectedPlaylist?['id']}'),
                              padding: EdgeInsets.fromLTRB(
                                waveVisuals(context).compact
                                    ? 16
                                    : desktop
                                    ? 40
                                    : 20,
                                waveVisuals(context).compact
                                    ? 16
                                    : desktop
                                    ? 34
                                    : 20,
                                waveVisuals(context).compact
                                    ? 16
                                    : desktop
                                    ? 40
                                    : 20,
                                32,
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1450,
                                ),
                                child: content(),
                              ),
                            ),
                          ),
                  ),
                  if (c.audio.current != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 28 : 10,
                        4,
                        desktop ? 28 : 10,
                        desktop ? 16 : 6,
                      ),
                      child: MiniPlayer(
                        controller: c,
                        onOpen: showPlayer,
                        artworkKey: miniArtwork,
                        onDragStart: beginPlayerDrag,
                        onDragUpdate: updatePlayerDrag,
                        onDragEnd: finishPlayerOpen,
                        onDragCancel: () => settlePlayer(false),
                      ),
                    ),
                  if (!desktop) bottomNavigation(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: handleKey,
      child: PopScope(
        canPop: !playerVisible,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && playerVisible) settlePlayer(false);
        },
        child: AnimatedBuilder(
          animation: playerReveal,
          child: shell,
          builder: (context, child) {
            final extent = playerReveal.value;
            final shift =
                (1 - extent) * MediaQuery.sizeOf(context).height * .22;
            return Stack(
              children: [
                ExcludeFocus(
                  excluding: playerVisible,
                  child: ExcludeSemantics(
                    excluding: playerVisible,
                    child: IgnorePointer(
                      ignoring: playerVisible,
                      child: TickerMode(enabled: !playerVisible, child: child!),
                    ),
                  ),
                ),
                if (playerVisible) ...[
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .22 * extent),
                    ),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: extent.clamp(0, 1),
                      child: Transform.translate(
                        offset: Offset(0, shift),
                        child: Material(
                          key: const Key('full-player'),
                          color: waveVisuals(context).background,
                          child: SafeArea(
                            child: PlayerPage(
                              controller: c,
                              initialTrack: previewTrack,
                              onMore: more,
                              onClose: () => settlePlayer(false),
                              artworkKey: fullArtwork,
                              hideAlbum: extent < 1 && coverOrigin != null,
                              onDragStart: beginPlayerClose,
                              onDragUpdate: updatePlayerDrag,
                              onDragEnd: finishPlayerClose,
                              onDragCancel: () => settlePlayer(true),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (extent < 1 &&
                      coverOrigin != null &&
                      coverDestination != null &&
                      c.audio.current != null)
                    Positioned.fromRect(
                      rect: Rect.lerp(coverOrigin, coverDestination, extent)!,
                      child: IgnorePointer(
                        child: Artwork(
                          key: const Key('player-cover-transition'),
                          controller: c,
                          url: c.audio.current!.artwork,
                          size: Rect.lerp(
                            coverOrigin,
                            coverDestination,
                            extent,
                          )!.width,
                          radius: 8 + extent * 6,
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Rect? artworkRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  void preparePlayer() {
    if (playerVisible || (c.audio.current == null && previewTrack == null)) {
      return;
    }
    coverOrigin = previewTrack == null ? artworkRect(miniArtwork) : null;
    coverDestination = null;
    setState(() => playerVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !playerVisible) return;
      final rect = artworkRect(fullArtwork);
      if (rect != null) {
        final shift =
            (1 - playerReveal.value) * MediaQuery.sizeOf(context).height * .22;
        setState(() => coverDestination = rect.translate(0, -shift));
      }
    });
  }

  void beginPlayerDrag() {
    playerTransition++;
    playerReveal.stop();
    preparePlayer();
    dragOrigin = playerReveal.value;
  }

  void beginPlayerClose() {
    playerTransition++;
    playerReveal.stop();
    dragOrigin = playerReveal.value;
    coverOrigin = previewTrack == null ? artworkRect(miniArtwork) : null;
    coverDestination = artworkRect(fullArtwork);
  }

  void updatePlayerDrag(double distance) {
    if (!playerVisible) return;
    final travel = MediaQuery.sizeOf(context).height * .7;
    playerReveal.value = (dragOrigin - distance / travel).clamp(0, 1);
  }

  void finishPlayerOpen(double velocity) =>
      settlePlayer(playerReveal.value > .22 || velocity < -550);
  void finishPlayerClose(double velocity) =>
      settlePlayer(!(playerReveal.value < .78 || velocity > 550));

  Future<void> settlePlayer(bool open) async {
    final revision = ++playerTransition;
    if (open) preparePlayer();
    if (!playerVisible) return;
    final still =
        c.customization.reducedMotion ||
        MediaQuery.disableAnimationsOf(context);
    try {
      await playerReveal
          .animateTo(
            open ? 1 : 0,
            duration: still ? Duration.zero : const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || revision != playerTransition) return;
    if (!open) {
      setState(() {
        playerVisible = false;
        previewTrack = null;
      });
    }
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape && playerVisible) {
      settlePlayer(false);
      return KeyEventResult.handled;
    }
    if (!(c.preferences.getBool('nativeHotkeys') ?? true)) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final control = HardwareKeyboard.instance.isControlPressed;
    if (event.logicalKey == LogicalKeyboardKey.space &&
        c.audio.current != null &&
        c.canControl) {
      run(c, c.audio.player.playing ? c.audio.pause : c.audio.play);
    } else if (control &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        c.canControl) {
      run(c, c.audio.skipToNext);
    } else if (control &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        c.canControl) {
      run(c, c.audio.skipToPrevious);
    } else if (control &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        !playerVisible) {
      navigate(WavePage.search);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget sidebar() => Container(
    width: 232,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: waveVisuals(context).line)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(21, 28, 21, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Brand(animated: c.settings['reducedMotion'] != true),
          const SizedBox(height: 36),
          Padding(
            padding: EdgeInsets.only(left: 12, bottom: 12),
            child: Text(
              wt('native.0c456a489e', context: context),
              style: TextStyle(
                color: waveVisuals(context).muted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final item in [
                    WavePage.home,
                    WavePage.library,
                    WavePage.search,
                    WavePage.liked,
                    WavePage.rooms,
                  ])
                    navItem(item),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: Icon(
                      Icons.nightlight_outlined,
                      size: 19,
                      color: waveVisuals(context).muted,
                    ),
                    title: Text(
                      wt('native.a3e784c186', context: context),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: waveVisuals(context).muted,
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => LofiPage(controller: c, onMore: more),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 12, bottom: 9),
                      child: Text(
                        wt('native.0a0be598ca', context: context),
                        style: TextStyle(
                          color: waveVisuals(context).muted,
                          fontSize: 9,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  for (final item in [
                    WavePage.sources,
                    WavePage.downloads,
                    WavePage.devices,
                  ])
                    navItem(item),
                  if (c.playlists.isNotEmpty) const SizedBox(height: 20),
                  for (final playlist in c.playlists.take(4))
                    InkWell(
                      borderRadius: BorderRadius.circular(
                        waveRadius(context, 12),
                      ),
                      onTap: () {
                        setState(() {
                          selectedPlaylist = playlist;
                          page = WavePage.library;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Artwork(
                              controller: c,
                              url: playlist['artwork'] as String?,
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                playlist['name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          navItem(WavePage.settings),
          if (c.user?.admin == true) navItem(WavePage.admin),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 6,
                color: c.connected
                    ? const Color(0xff88a58d)
                    : waveVisuals(context).muted,
              ),
              const SizedBox(width: 7),
              Text(
                c.connected
                    ? wt('native.cf696d8d96', context: context)
                    : wt('native.1c8ad826bb', context: context),
                style: TextStyle(
                  fontSize: 9,
                  color: waveVisuals(context).muted,
                ),
              ),
              const Spacer(),
              Text('β', style: TextStyle(color: waveVisuals(context).accent)),
            ],
          ),
        ],
      ),
    ),
  );
  Widget navItem(WavePage value) {
    final active = page == value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: active ? waveVisuals(context).ink : Colors.transparent,
        borderRadius: BorderRadius.circular(waveRadius(context, 13)),
        child: InkWell(
          borderRadius: BorderRadius.circular(waveRadius(context, 13)),
          onTap: () => navigate(value),
          key: Key('nav-${value.name}'),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: waveVisuals(context).compact ? 9 : 13,
            ),
            child: Row(
              children: [
                Icon(
                  pageIcons[value.index],
                  size: 19,
                  color: active
                      ? waveVisuals(context).background
                      : waveVisuals(context).muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pageLabels[value.index],
                    style: TextStyle(
                      fontSize: 12,
                      color: active
                          ? waveVisuals(context).background
                          : waveVisuals(context).muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (active)
                  Icon(
                    Icons.circle,
                    size: 5,
                    color: waveVisuals(context).accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget topbar(bool desktop) => Container(
    height: waveVisuals(context).compact
        ? 60
        : desktop
        ? 86
        : 64,
    padding: EdgeInsets.symmetric(
      horizontal: desktop
          ? 40
          : MediaQuery.sizeOf(context).width < 360
          ? 16
          : 20,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: waveVisuals(context).line)),
    ),
    child: Row(
      children: [
        if (!desktop)
          Brand(size: 29, animated: c.settings['reducedMotion'] != true),
        if (desktop)
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: waveVisuals(context).muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: search,
                    decoration: InputDecoration(
                      hintText: wt('native.eaad77f8f4', context: context),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: scheduleSearch,
                    onSubmitted: (_) => doSearch(),
                  ),
                ),
                const SizedBox(width: 20),
              ],
            ),
          )
        else
          const Spacer(),
        IconButton(
          tooltip: wt('native.7ab03d602e', context: context),
          onPressed: () => navigate(WavePage.devices),
          icon: Icon(
            Icons.devices_rounded,
            size: 21,
            color: waveVisuals(context).muted,
          ),
        ),
        if (desktop)
          IconButton(
            tooltip: wt('native.16df3aa8af', context: context),
            onPressed: c.loading ? null : () => run(c, c.refresh),
            icon: Icon(
              Icons.sync_rounded,
              size: 21,
              color: waveVisuals(context).muted,
            ),
          )
        else
          PopupMenuButton<String>(
            key: const Key('mobile-menu'),
            tooltip: wt('native.bd23ec8a42', context: context),
            icon: Icon(
              Icons.more_horiz_rounded,
              color: waveVisuals(context).muted,
            ),
            onSelected: (value) {
              if (value == 'lofi') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LofiPage(controller: c),
                  ),
                );
              } else {
                navigate(
                  WavePage.values.firstWhere((item) => item.name == value),
                );
              }
            },
            itemBuilder: (_) => [
              for (final item in {
                'rooms': wt('native.200ba6b661', context: context),
                'lofi': wt('native.847e19da38', context: context),
                'sources': wt('native.5384db72a4', context: context),
                'downloads': wt('native.212ccf5938', context: context),
                'settings': wt('native.7f17c7c62a', context: context),
              }.entries)
                PopupMenuItem(value: item.key, child: Text(item.value)),
            ],
          ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(waveRadius(context, 30)),
          onTap: () => navigate(WavePage.profile),
          key: const Key('profile-link'),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: c.user?.avatar.isNotEmpty == true
                  ? Artwork(
                      controller: c,
                      url: c.user!.avatar,
                      size: 34,
                      radius: 20,
                    )
                  : CircleAvatar(
                      radius: 17,
                      backgroundColor: waveVisuals(context).accentSoft,
                      child: Text(
                        c.user!.displayName.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: waveVisuals(context).ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget bottomNavigation() => Padding(
    padding: const EdgeInsets.fromLTRB(5, 5, 5, 8),
    child: Row(
      children: [
        for (final value in [WavePage.home, WavePage.search, WavePage.library])
          Expanded(
            child: InkWell(
              onTap: () => navigate(value),
              key: Key('nav-${value.name}'),
              borderRadius: BorderRadius.circular(waveRadius(context, 12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pageIcons[value.index],
                      color: page == value
                          ? waveVisuals(context).ink
                          : waveVisuals(context).muted,
                      size: 23,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value == WavePage.rooms
                          ? wt('native.11688c1649', context: context)
                          : pageLabels[value.index],
                      style: TextStyle(
                        fontSize: 9,
                        color: page == value
                            ? waveVisuals(context).ink
                            : waveVisuals(context).muted,
                        fontWeight: page == value
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget content() {
    final pending =
        c.loading &&
        switch (page) {
          WavePage.home ||
          WavePage.library ||
          WavePage.liked => c.tracks.isEmpty,
          WavePage.rooms => c.rooms.isEmpty,
          WavePage.sources => c.integrations.isEmpty,
          WavePage.devices => c.devices.isEmpty,
          _ => false,
        };
    if (pending) {
      return Column(
        key: const Key('route-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WaveSkeletonBlock(width: 200, height: 30),
          const SizedBox(height: 12),
          const WaveSkeletonBlock(width: 160),
          const SizedBox(height: 28),
          WaveLoadingList(
            label: wt(
              'native.211621443e',
              values: {'p0': (pageLabels[page.index])},
              context: context,
            ),
          ),
        ],
      );
    }
    return switch (page) {
      WavePage.home => home(),
      WavePage.library => library(),
      WavePage.search => searchPage(),
      WavePage.liked => library(liked: true),
      WavePage.rooms => roomPage(),
      WavePage.sources => sourcesPage(),
      WavePage.downloads => downloads(),
      WavePage.devices => devicesPage(),
      WavePage.profile => profile(),
      WavePage.settings => settingsPage(),
      WavePage.admin => AdminPage(controller: c),
    };
  }

  Widget section(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 30, bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
  Widget tracksList(List<WaveTrack> items) => Column(
    children: [
      for (final track in items)
        TrackRow(
          controller: c,
          track: track,
          queue: items,
          onMore: () => more(track),
        ),
    ],
  );
  Widget home() {
    final hour = DateTime.now().hour;
    final greeting = hour >= 18
        ? wt('native.37f9f18bdc', context: context)
        : hour >= 12
        ? wt('native.51d822d031', context: context)
        : hour >= 5
        ? wt('native.d73c91bbc4', context: context)
        : wt('native.194858b25f', context: context);
    final local = c.tracks.where((t) => t.playable).toList();
    final recent = c.history
        .map((entry) => c.track(entry['trackId'] as String?))
        .whereType<WaveTrack>()
        .take(6)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          '$greeting, ${c.user!.displayName}',
          wt('native.10da2df4b2', context: context),
          eyebrow: wt('native.4fc610d5e7', context: context),
          action: OutlinedButton.icon(
            onPressed: () => navigate(WavePage.sources),
            icon: const Icon(Icons.hub_outlined, size: 17),
            label: Text(wt('native.642fcf95d9', context: context)),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth < 450
                ? constraints.maxWidth
                : ((constraints.maxWidth - 12) / 2).clamp(0.0, 270.0);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                quickCard(
                  wt('native.d3aa3fa13d', context: context),
                  wt(
                    'native.e352fa0553',
                    values: {'p0': (c.likedIds.length)},
                    context: context,
                  ),
                  Icons.favorite_border,
                  () => navigate(WavePage.liked),
                  width: cardWidth,
                ),
                quickCard(
                  wt('native.90e8504b03', context: context),
                  wt('native.4e7b973c7e', context: context),
                  Icons.offline_pin_outlined,
                  () => navigate(WavePage.downloads),
                  width: cardWidth,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        WaveHero(
          controller: c,
          empty: local.isEmpty,
          reducedMotion: c.settings['reducedMotion'] == true,
          onPlay: () => local.isEmpty
              ? run(c, c.uploadAudio)
              : run(
                  c,
                  () => c.play((local.toList()..shuffle()).first, list: local),
                ),
        ),
        section(
          wt('native.d73ebed4df', context: context),
          trailing: TextButton(
            onPressed: () => navigate(WavePage.library),
            child: Text(wt('native.51d1aabe9f', context: context)),
          ),
        ),
        if (c.playlists.isEmpty)
          Surface(
            child: Row(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  color: waveVisuals(context).accent,
                  size: 32,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wt('native.a3ea6451ed', context: context),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        wt('native.637437750e', context: context),
                        style: TextStyle(
                          color: waveVisuals(context).muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: wt('native.6ce6f8d86e', context: context),
                  onPressed: newPlaylist,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          )
        else
          playlistGrid(),
        section(
          recent.isEmpty
              ? wt('native.b2fa6a1cea', context: context)
              : wt('native.b73d4d1b29', context: context),
        ),
        if (recent.isNotEmpty)
          tracksList(recent)
        else if (c.tracks.isNotEmpty)
          tracksList(c.tracks.take(5).toList())
        else
          EmptyState(
            wt('native.c55ae9eb3e', context: context),
            wt('native.a468ce3ecb', context: context),
            action: FilledButton.icon(
              onPressed: () => navigate(WavePage.sources),
              icon: const Icon(Icons.hub_outlined),
              label: Text(wt('native.db4afdc056', context: context)),
            ),
          ),
        const SizedBox(height: 24),
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => LofiPage(controller: c, onMore: more),
            ),
          ),
          borderRadius: BorderRadius.circular(waveRadius(context, 22)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(waveRadius(context, 22)),
            child: Container(
              height: 196,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/forest.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      waveVisuals(context).ink.withValues(alpha: .7),
                      waveVisuals(context).ink.withValues(alpha: .3),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wt('native.5e2a1d79c9', context: context),
                      style: TextStyle(
                        color: waveVisuals(context).background,
                        fontSize: 9,
                        letterSpacing: 1.6,
                      ),
                    ),
                    Spacer(),
                    Text(
                      wt('native.31c118bf9d', context: context),
                      style: TextStyle(
                        color: waveVisuals(context).background,
                        fontSize: 31,
                        height: 1.05,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      wt('native.bf064cd50f', context: context),
                      style: TextStyle(
                        color: waveVisuals(context).background,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 28),
          child: Text(
            wt('native.323bd869d4', context: context),
            style: TextStyle(color: waveVisuals(context).muted, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget quickCard(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback tap, {
    required double width,
  }) => SizedBox(
    width: width,
    child: Material(
      color: waveVisuals(context).surface,
      borderRadius: BorderRadius.circular(waveRadius(context, 16)),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(waveRadius(context, 16)),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 39,
                decoration: BoxDecoration(
                  color: waveVisuals(context).accentSoft,
                  borderRadius: BorderRadius.circular(waveRadius(context, 10)),
                ),
                child: Icon(icon, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      style: TextStyle(
                        color: waveVisuals(context).muted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> newPlaylist() async {
    final name = await askText(
      context,
      wt('native.7984f2471a', context: context),
      wt('native.9200137ae9', context: context),
    );
    if (name != null) await run(c, () => c.playlist(name));
  }

  Widget playlistGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth < 500
          ? 2
          : constraints.maxWidth < 850
          ? 3
          : 5;
      final width = (constraints.maxWidth - (count - 1) * 18) / count;
      return Wrap(
        spacing: 18,
        runSpacing: 22,
        children: [
          for (final playlist in c.playlists)
            SizedBox(
              width: width,
              child: InkWell(
                borderRadius: BorderRadius.circular(waveRadius(context, 18)),
                onTap: () => setState(() {
                  selectedPlaylist = playlist;
                  page = WavePage.library;
                }),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Artwork(
                      controller: c,
                      url: playlist['artwork'] as String?,
                      size: width,
                      radius: 17,
                      icon: Icons.queue_music_rounded,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      playlist['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      wt(
                        'native.dcb57004b9',
                        values: {
                          'p0': ((playlist['trackIds'] as List?)?.length ?? 0),
                        },
                        context: context,
                      ),
                      style: TextStyle(
                        color: waveVisuals(context).muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget library({bool liked = false}) {
    var items = c.tracks;
    if (liked || filter == 'liked') {
      items = items.where((t) => c.likedIds.contains(t.id)).toList();
    }
    if (filter == 'local' && !liked) {
      items = items.where((t) => t.source == 'local').toList();
    }
    if (selectedPlaylist != null) {
      final ids = List<String>.from(selectedPlaylist!['trackIds'] ?? []);
      items = ids.map(c.track).whereType<WaveTrack>().toList();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedPlaylist != null)
          TextButton.icon(
            onPressed: () => setState(() => selectedPlaylist = null),
            icon: const Icon(Icons.arrow_back, size: 17),
            label: Text(wt('native.082b4a891b', context: context)),
          ),
        PageHeading(
          selectedPlaylist?['name'] as String? ??
              (liked
                  ? wt('native.d3aa3fa13d', context: context)
                  : wt('native.27925da08c', context: context)),
          selectedPlaylist?['description'] as String? ??
              wt('native.9221337472', context: context),
          eyebrow: wt('native.708d386559', context: context),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            if (!liked && selectedPlaylist == null)
              for (final entry in {
                'all': wt('native.7b4cc84722', context: context),
                'playlists': wt('native.5cbd56308f', context: context),
                'liked': wt('native.d3aa3fa13d', context: context),
                'local': wt('native.da39e0cc91', context: context),
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: filter == entry.key,
                  onSelected: (_) => setState(() => filter = entry.key),
                  selectedColor: waveVisuals(context).accentSoft,
                  showCheckmark: false,
                ),
            FilledButton.icon(
              onPressed: c.online ? () => run(c, c.uploadAudio) : null,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(wt('native.99855bf52d', context: context)),
            ),
            OutlinedButton.icon(
              onPressed: c.online ? newPlaylist : null,
              icon: const Icon(Icons.queue_music, size: 17),
              label: Text(wt('native.d6ab7b0b5a', context: context)),
            ),
          ],
        ),
        if (c.uploadProgress != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: LinearProgressIndicator(
              value: c.uploadProgress,
              color: waveVisuals(context).accent,
            ),
          ),
        const SizedBox(height: 26),
        if (filter == 'playlists' && !liked && selectedPlaylist == null)
          playlistGrid()
        else if (items.isEmpty)
          EmptyState(
            liked
                ? wt('native.46298dcf5e', context: context)
                : wt('native.1adc5a6a23', context: context),
            wt('native.29f6c0dba0', context: context),
            action: OutlinedButton(
              onPressed: () => navigate(WavePage.sources),
              child: Text(wt('native.388ca31bac', context: context)),
            ),
          )
        else
          tracksList(items),
        if (selectedPlaylist != null)
          Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: () => run(c, () async {
                  final name = await askText(
                    context,
                    wt('native.fbb72c35d6', context: context),
                    wt('native.3de49828e8', context: context),
                    value: selectedPlaylist!['name'] as String,
                  );
                  if (name != null) {
                    await c.api.call(
                      '/api/playlists/${selectedPlaylist!['id']}',
                      method: 'PATCH',
                      data: {'name': name},
                    );
                    selectedPlaylist = null;
                    await c.refresh();
                  }
                }),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: Text(wt('native.715e8f0c32', context: context)),
              ),
              TextButton.icon(
                onPressed: () => confirm(
                  wt('native.2eb4f15128', context: context),
                  wt('native.75710f1731', context: context),
                  () async {
                    await c.api.call(
                      '/api/playlists/${selectedPlaylist!['id']}',
                      method: 'DELETE',
                    );
                    setState(() => selectedPlaylist = null);
                    await c.refresh();
                  },
                ),
                icon: const Icon(Icons.delete_outline, size: 17),
                label: Text(wt('native.86ea33aef5', context: context)),
              ),
            ],
          ),
      ],
    );
  }

  void scheduleSearch(String value) {
    if (page != WavePage.search) navigate(WavePage.search);
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 400), doSearch);
  }

  Future<void> doSearch() async {
    if (!mounted) return;
    final revision = ++searchRequest;
    setState(() => searching = true);
    await run(c, () => c.search(search.text, source: source));
    if (mounted && revision == searchRequest) setState(() => searching = false);
  }

  Widget searchPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        wt('native.682466a401', context: context),
        wt('native.fb10bb6c43', context: context),
        eyebrow: wt('native.9bd84125bc', context: context),
      ),
      if (MediaQuery.sizeOf(context).width < 900)
        TextField(
          controller: search,
          onChanged: scheduleSearch,
          onSubmitted: (_) => doSearch(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: wt('native.bbd9181561', context: context),
            suffixIcon: IconButton(
              onPressed: doSearch,
              tooltip: wt('native.58212e541c', context: context),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in {
              'all': wt('native.58b59eb005', context: context),
              'local': wt('native.1aa3589e13', context: context),
              'youtube': 'YouTube',
              'spotify': 'Spotify',
              'soundcloud': 'SoundCloud',
              'yandex': wt('native.0fb8bc0888', context: context),
            }.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: source == entry.key,
                  showCheckmark: false,
                  selectedColor: waveVisuals(context).accentSoft,
                  onSelected: (_) {
                    setState(() => source = entry.key);
                    doSearch();
                  },
                ),
              ),
          ],
        ),
      ),
      if (c.suggestion != null)
        Padding(
          padding: const EdgeInsets.only(top: 15),
          child: TextButton(
            onPressed: () {
              search.text = c.suggestion!;
              doSearch();
            },
            child: Text(
              wt(
                'native.f1b3941857',
                values: {'p0': (c.suggestion)},
                context: context,
              ),
            ),
          ),
        ),
      const SizedBox(height: 20),
      if (searching)
        const WaveLoadingList(key: Key('search-loading'))
      else if (c.results.isNotEmpty || c.artistResults.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.artistResults.isNotEmpty) ...[
              Text(
                wt('search.artists', context: context),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final artist in c.artistResults)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 176,
                          child: OutlinedButton(
                            key: ValueKey('search-artist-${artist['id']}'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(14),
                              backgroundColor: waveVisuals(context).surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: () => run(c, () async {
                              search.text = artist['name']?.toString() ?? '';
                              await c.searchArtist(artist);
                            }),
                            child: Column(
                              children: [
                                ClipOval(
                                  child: Artwork(
                                    controller: c,
                                    url: artist['artwork']?.toString() ?? '',
                                    size: 66,
                                    radius: 0,
                                  ),
                                ),
                                const SizedBox(height: 11),
                                Text(
                                  artist['name']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  providerName(
                                    artist['source']?.toString() ?? 'local',
                                  ),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: waveVisuals(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
            ],
            if (c.results.isNotEmpty) tracksList(c.results),
          ],
        )
      else
        EmptyState(
          search.text.isEmpty
              ? wt('native.6d7be8c94d', context: context)
              : wt('native.e61d08951b', context: context),
          search.text.isEmpty
              ? wt('native.01529b9d5e', context: context)
              : wt('native.10c727a4cc', context: context),
        ),
      if (search.text.startsWith('https://'))
        OutlinedButton.icon(
          onPressed: () => run(c, () => c.resolve(search.text)),
          icon: const Icon(Icons.link_rounded),
          label: Text(wt('native.0556f90ffc', context: context)),
        ),
    ],
  );
  Future<void> showPlayer({WaveTrack? track}) async {
    setState(() => previewTrack = track);
    if (c.desktop.mini) await run(c, c.desktop.toggleMini);
    if (mounted) await settlePlayer(true);
  }

  Future<void> more(WaveTrack track) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Artwork(controller: c, url: track.artwork),
              title: Text(
                track.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(track.artist),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(wt('native.f130436a3b', context: context)),
              onTap: () {
                Navigator.pop(sheet);
                run(c, () => c.audio.addQueueItem(c.audio.item(track)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(wt('native.df0c76065d', context: context)),
              onTap: () async {
                Navigator.pop(sheet);
                final selected = await showWaveDialog<Json>(
                  context: context,
                  builder: (dialog) => SimpleDialog(
                    title: Text(wt('native.81524f9e71', context: context)),
                    children: [
                      for (final playlist in c.playlists)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(dialog, playlist),
                          child: Text(playlist['name'] as String),
                        ),
                      if (c.playlists.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            wt('native.9feaa9c30e', context: context),
                          ),
                        ),
                    ],
                  ),
                );
                if (selected != null) {
                  await run(c, () => c.addToPlaylist(selected, track));
                }
              },
            ),
            if (track.offline)
              ListTile(
                leading: Icon(
                  c.cache.contains(track.id)
                      ? Icons.offline_pin_outlined
                      : Icons.download_rounded,
                ),
                title: Text(
                  c.cache.contains(track.id)
                      ? wt('native.e72e7819a3', context: context)
                      : wt('native.5fbca5dea7', context: context),
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  run(c, () => c.cache.save(track, manual: true));
                },
              ),
            if (c.cache.contains(track.id))
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(wt('native.2266a8f9e2', context: context)),
                onTap: () {
                  Navigator.pop(sheet);
                  run(c, () => c.cache.remove(track.id));
                },
              ),
            ListTile(
              leading: const Icon(Icons.lyrics_outlined),
              title: Text(wt('native.58131c476d', context: context)),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(showPlayer(track: track));
              },
            ),
            if (track.sourceUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(
                  wt(
                    'native.22618d4822',
                    values: {'p0': (track.sourceName)},
                    context: context,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  run(c, () => c.openUrl(track.sourceUrl));
                },
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(wt('native.69d7d7248a', context: context)),
              onTap: () {
                Clipboard.setData(
                  ClipboardData(text: '${c.appUrl}/?track=${track.id}'),
                );
                Navigator.pop(sheet);
                c.tell(wt('native.dd68e0027d', context: context));
              },
            ),
            if (c.online && track.source == 'local')
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(wt('native.8c343d516d', context: context)),
                onTap: () {
                  Navigator.pop(sheet);
                  confirm(
                    wt(
                      'native.0f29ff7f79',
                      values: {'p0': (track.title)},
                      context: context,
                    ),
                    wt('native.3f54d53ce0', context: context),
                    () async {
                      await c.api.call(
                        '/api/tracks/${track.id}',
                        method: 'DELETE',
                      );
                      await c.refresh();
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> confirm(
    String title,
    String text,
    Future<void> Function() action,
  ) async {
    final accepted = await showWaveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(wt('native.a90b7cbc92', context: context)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(wt('native.86ea33aef5', context: context)),
          ),
        ],
      ),
    );
    if (accepted == true) await run(c, action);
  }

  Widget sourcesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        wt('native.129336147d', context: context),
        wt('native.28e8073601', context: context),
        eyebrow: wt('native.96aa77adea', context: context),
      ),
      for (final entry in c.integrations.where(
        (item) => item['provider'] != 'discord',
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Surface(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: waveVisuals(context).accentSoft,
                    borderRadius: BorderRadius.circular(
                      waveRadius(context, 15),
                    ),
                  ),
                  child: Icon(
                    sourceIcon(entry['provider'] as String),
                    color: providerColor(entry['provider'] as String),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        providerName(entry['provider'] as String),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        entry['connected'] == true
                            ? wt(
                                'native.8343afbb45',
                                values: {'p0': (entry['displayName'] ?? '')},
                                context: context,
                              )
                            : entry['provider'] == 'soundcloud' &&
                                  (entry['searchAvailable'] == true ||
                                      object(
                                            object(
                                              c.config['providers'],
                                            )['soundcloud'],
                                          )['searchAvailable'] ==
                                          true)
                            ? wt('native.a9f3831f36', context: context)
                            : entry['reason'] as String? ??
                                  wt('native.993a71a598', context: context),
                        style: TextStyle(
                          fontSize: 11,
                          color: waveVisuals(context).muted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (entry['connected'] == true)
                  Column(
                    children: [
                      FilledButton(
                        onPressed: () =>
                            sourcePlaylists(entry['provider'] as String),
                        child: Text(wt('native.081b1d81c6', context: context)),
                      ),
                      TextButton(
                        onPressed: () => run(
                          c,
                          () =>
                              c.disconnectProvider(entry['provider'] as String),
                        ),
                        child: Text(wt('native.94d07a2171', context: context)),
                      ),
                    ],
                  )
                else
                  OutlinedButton(
                    onPressed: entry['configured'] == true
                        ? () => run(
                            c,
                            () =>
                                c.connectProvider(entry['provider'] as String),
                          )
                        : null,
                    child: Text(
                      entry['configured'] == true
                          ? wt('native.124298ec71', context: context)
                          : wt('native.656d8c4f40', context: context),
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (c.integrations.isEmpty)
        EmptyState(
          wt('native.e8ee34a373', context: context),
          wt('native.e8c84710a2', context: context),
          icon: Icons.hub_outlined,
        ),
      const SizedBox(height: 10),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wt('native.cd9296f478', context: context),
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              wt('native.0d6b25bb78', context: context),
              style: TextStyle(
                color: waveVisuals(context).muted,
                height: 1.7,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => run(c, c.uploadAudio),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(wt('native.d94f27d311', context: context)),
                ),
                OutlinedButton.icon(
                  onPressed: () => run(c, c.importFile),
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: Text(wt('native.f1b4dac46c', context: context)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final link = await askText(
                      context,
                      wt('native.8b01571e48', context: context),
                      wt('native.819abda8d9', context: context),
                    );
                    if (link != null) await run(c, () => c.resolve(link));
                  },
                  icon: const Icon(Icons.link),
                  label: Text(wt('native.eaf0e31f63', context: context)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              wt('native.824436c0c7', context: context),
              style: TextStyle(
                color: waveVisuals(context).muted,
                fontSize: 11,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      TextButton.icon(
        onPressed: () => run(c, c.refresh),
        icon: const Icon(Icons.refresh_rounded),
        label: Text(wt('native.3bdfeea56b', context: context)),
      ),
    ],
  );
  Future<void> sourcePlaylists(String provider) async {
    await run(c, () async {
      final data = await c.api.call('/api/integrations/$provider/playlists');
      if (!mounted) return;
      final lists = objects(data['playlists']);
      final liked = object(data['liked']);
      if (liked.isNotEmpty) lists.add(liked);
      await showWaveDialog<void>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: Text(
            wt(
              'native.03047eef41',
              values: {'p0': (providerName(provider))},
              context: context,
            ),
          ),
          children: [
            for (final playlist in lists)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(dialog);
                  previewImport(provider, playlist);
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(playlist['name'] as String),
                          Text(
                            wt(
                              'native.dcb57004b9',
                              values: {'p0': (playlist['trackCount'] ?? '')},
                            ),
                            style: TextStyle(
                              color: waveVisuals(context).muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 17),
                  ],
                ),
              ),
            if (lists.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text(wt('native.9789a336b5', context: context)),
              ),
          ],
        ),
      );
    });
  }

  Future<void> previewImport(String provider, Json playlist) async {
    await run(c, () async {
      final response = await c.api.call(
        '/api/integrations/$provider/playlists/${Uri.encodeComponent(playlist['id'] as String)}/tracks',
      );
      if (!mounted) return;
      final items = objects(response['tracks']);
      final selected = items
          .map((t) => (t['sourceId'] ?? t['id']) as String)
          .toSet();
      bool allPages = true;
      await showWaveDialog<void>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: Text(playlist['name'] as String),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(wt('native.00860b84d0', context: context)),
                    subtitle: Text(wt('native.f901da5358', context: context)),
                    value: allPages,
                    onChanged: (v) => update(() => allPages = v),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final t in items)
                          CheckboxListTile(
                            value:
                                allPages ||
                                selected.contains(t['sourceId'] ?? t['id']),
                            onChanged: allPages
                                ? null
                                : (v) => update(() {
                                    final id =
                                        (t['sourceId'] ?? t['id']) as String;
                                    if (v == true) {
                                      selected.add(id);
                                    } else {
                                      selected.remove(id);
                                    }
                                  }),
                            title: Text(
                              t['title'] as String? ??
                                  wt('native.32b74a3c47', context: context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(t['artist'] as String? ?? ''),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(wt('native.f6dab074d7', context: context)),
              ),
              FilledButton(
                onPressed: allPages || selected.isNotEmpty
                    ? () async {
                        Navigator.pop(dialog);
                        await run(c, () async {
                          final data = await c.api.call(
                            '/api/integrations/$provider/import',
                            method: 'POST',
                            data: {
                              'playlistId': playlist['id'],
                              if (!allPages) 'trackIds': selected.toList(),
                            },
                          );
                          await c.refresh();
                          c.tell(
                            wt(
                              'native.b2ac0da1b6',
                              values: {'p0': (data['imported'])},
                            ),
                          );
                        });
                      }
                    : null,
                child: Text(wt('native.e8b58dacdf', context: context)),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget downloads() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        wt('native.139fd495d9', context: context),
        wt(
          'native.880e44a69b',
          values: {
            'p0': localizedNumber(
              c.cache.bytes / 1024 / 1024,
              decimalDigits: 1,
              context: context,
            ),
            'p1': (c.cache.limitMB),
          },
          context: context,
        ),
        eyebrow: wt('native.28e756053a', context: context),
      ),
      LinearProgressIndicator(
        value: (c.cache.bytes / (c.cache.limitMB * 1024 * 1024)).clamp(0, 1),
        color: waveVisuals(context).accent,
        backgroundColor: waveVisuals(context).accentSoft,
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => run(c, () => c.cache.clear()),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(wt('native.cfe7094211', context: context)),
          ),
          TextButton(
            onPressed: () => confirm(
              wt('native.c484e0bf9e', context: context),
              wt('native.a2f281e0fb', context: context),
              () => c.cache.clear(includingDownloads: true),
            ),
            child: Text(wt('native.fc62d0d702', context: context)),
          ),
        ],
      ),
      for (final entry in c.cache.progress.entries)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.track(entry.key)?.title ??
                    wt('native.9db7ca043f', context: context),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 9),
              LinearProgressIndicator(
                value: entry.value > 0 ? entry.value : null,
                color: waveVisuals(context).accent,
              ),
            ],
          ),
        ),
      const SizedBox(height: 22),
      if (c.cache.entries.isEmpty)
        EmptyState(
          wt('native.50c21d127f', context: context),
          wt('native.078fb4ae47', context: context),
          icon: Icons.offline_pin_outlined,
        )
      else
        for (final entry in c.cache.entries.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TrackRow(
                  controller: c,
                  track: WaveTrack(object(object(entry.value)['track'])),
                  onMore: () =>
                      more(WaveTrack(object(object(entry.value)['track']))),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 68),
                  child: Text(
                    wt(
                      'native.9e516806ab',
                      values: {
                        'p0': (object(entry.value)['manual'] == true
                            ? wt('native.b6d57513a1', context: context)
                            : wt('native.fae9d01025', context: context)),
                        'p1': localizedNumber(
                          number(object(entry.value)['bytes']) / 1024 / 1024,
                          decimalDigits: 1,
                          context: context,
                        ),
                      },
                      context: context,
                    ),
                    style: TextStyle(
                      color: waveVisuals(context).muted,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
  Widget roomPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        wt('native.200ba6b661', context: context),
        wt('native.c3acebae3e', context: context),
        eyebrow: wt('native.cfb828faf3', context: context),
      ),
      if (c.room == null) ...[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () async {
                final name = await askText(
                  context,
                  wt('native.2e0b4996ef', context: context),
                  wt('native.55c12495ec', context: context),
                );
                if (name != null) await run(c, () => c.createRoom(name));
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(wt('native.3643850b0a', context: context)),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final code = await askText(
                  context,
                  wt('native.2230603bcd', context: context),
                  wt('native.c4627815d7', context: context),
                );
                if (code != null) await run(c, () => c.joinRoom(code));
              },
              icon: const Icon(Icons.link_rounded),
              label: Text(wt('native.0b7a3e93f1', context: context)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        for (final room in c.rooms)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Surface(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.spatial_audio_off_outlined,
                  size: 32,
                  color: waveVisuals(context).accent,
                ),
                title: Text(
                  room['name'] as String,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  wt(
                    'native.2414024420',
                    values: {'p0': (objects(room['members']).length)},
                    context: context,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_rounded),
                onTap: () => run(c, () => c.enterRoom(room)),
              ),
            ),
          ),
        if (c.rooms.isEmpty)
          EmptyState(
            wt('native.cd705fb252', context: context),
            wt('native.a82ae8303b', context: context),
            icon: Icons.spatial_audio_off_outlined,
          ),
      ] else ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(waveRadius(context, 22)),
          child: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/forest.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              color: waveVisuals(context).ink.withValues(alpha: .55),
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.connected
                        ? wt('native.e191ae678f', context: context)
                        : wt('native.0a4c6ceeee', context: context),
                    style: TextStyle(
                      color: waveVisuals(context).background,
                      fontSize: 9,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    c.room!['name'] as String,
                    style: TextStyle(
                      color: waveVisuals(context).background,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: waveVisuals(context).background,
                          foregroundColor: waveVisuals(context).ink,
                        ),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text:
                                  '${c.appUrl}/?room=${c.room!['inviteCode']}',
                            ),
                          );
                          c.tell(wt('native.916b1a3bbf', context: context));
                        },
                        icon: const Icon(Icons.link_rounded),
                        label: Text(wt('native.2c8e25954f', context: context)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: waveVisuals(context).background,
                        ),
                        onPressed: () => run(c, c.leaveRoom),
                        child: Text(wt('native.5aeda8f0be', context: context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (c.audio.current != null)
          MiniPlayer(controller: c, onOpen: showPlayer),
        section(wt('native.1d2a1d354c', context: context)),
        Surface(
          child: Column(
            children: [
              for (final member in objects(c.room!['members']))
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: waveVisuals(context).accentSoft,
                      child: Text(
                        (member['displayName'] as String? ?? '?').substring(
                          0,
                          1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member['displayName'] as String? ??
                                wt('native.76ffe26d00', context: context),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            member['role'] == 'owner' ||
                                    member['userId'] == c.room!['ownerId']
                                ? wt('native.d73e431d49', context: context)
                                : member['canControl'] == true
                                ? wt('native.0554078156', context: context)
                                : wt('native.6a4bbeffcc', context: context),
                            style: TextStyle(
                              color: waveVisuals(context).muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.room!['ownerId'] == c.user!.id &&
                        member['userId'] != c.user!.id)
                      Switch(
                        value: member['canControl'] == true,
                        onChanged: (v) => run(
                          c,
                          () => c.roomPermission(member['userId'] as String, v),
                        ),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.headphones_outlined,
                          size: 19,
                          color: waveVisuals(context).muted,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        section(wt('native.6174ccc7f5', context: context)),
        Surface(
          child: Column(
            children: [
              SizedBox(
                height: 300,
                child: ListView(
                  reverse: true,
                  children: [
                    for (final message in c.messages.reversed)
                      Align(
                        alignment: message['userId'] == c.user!.id
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(13),
                          constraints: const BoxConstraints(maxWidth: 440),
                          decoration: BoxDecoration(
                            color: message['userId'] == c.user!.id
                                ? waveVisuals(context).accentSoft
                                : waveVisuals(context).background,
                            borderRadius: BorderRadius.circular(
                              waveRadius(context, 14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['displayName'] as String? ?? '',
                                style: TextStyle(
                                  color: waveVisuals(context).muted,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 5),
                              SelectableText(message['text'] as String? ?? ''),
                            ],
                          ),
                        ),
                      ),
                    if (c.messages.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(30),
                        child: Text(
                          wt('native.7abdd3e513', context: context),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: waveVisuals(context).muted),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: chat,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintText: wt('native.e46d8ce0ed', context: context),
                        counterText: '',
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: c.connected ? sendMessage : null,
                    tooltip: wt('native.76dcf737a6', context: context),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          c.canControl
              ? wt('native.ebd33b8d52', context: context)
              : wt('native.7f5dea692a', context: context),
          style: TextStyle(color: waveVisuals(context).muted, fontSize: 12),
        ),
      ],
    ],
  );
  Future<void> sendMessage() async {
    final value = chat.text;
    await run(c, () async {
      await c.roomMessage(value);
      chat.clear();
    });
  }

  Widget devicesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        wt('native.fec96a4982', context: context),
        wt('native.06722aad25', context: context),
        eyebrow: wt('native.d3b6a00135', context: context),
      ),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wt('native.5e1f41132a', context: context),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              c.deviceName,
              style: TextStyle(color: waveVisuals(context).muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.volume_down_rounded, size: 20),
                Expanded(
                  child: Slider(
                    value: c.audio.volume.clamp(0, 1),
                    onChanged: (v) =>
                        run(c, () => c.transport('volume', {'volume': v})),
                  ),
                ),
                const Icon(Icons.volume_up_outlined, size: 20),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      for (final device in c.devices)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Surface(
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      device['kind'] == 'android' || device['kind'] == 'ios'
                          ? Icons.smartphone_rounded
                          : device['kind'] == 'web'
                          ? Icons.language_rounded
                          : Icons.computer_outlined,
                      size: 30,
                      color: waveVisuals(context).accent,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device['name'] as String? ??
                                wt('native.bc791dbe7e', context: context),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            device['id'] == c.deviceId
                                ? wt('native.4eca465a4a', context: context)
                                : device['online'] == true
                                ? wt('native.011e2099f2', context: context)
                                : wt('native.67b99cc9bf', context: context),
                            style: TextStyle(
                              color: waveVisuals(context).muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (device['id'] != c.deviceId)
                      OutlinedButton(
                        onPressed:
                            device['online'] == true && c.audio.current != null
                            ? () => run(
                                c,
                                () => c.transfer(device['id'] as String),
                              )
                            : null,
                        child: Text(wt('native.49daba7f72', context: context)),
                      ),
                  ],
                ),
                if (device['id'] != c.deviceId && device['online'] == true) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        tooltip: wt('native.1b2692a600', context: context),
                        onPressed: () => run(
                          c,
                          () => c.commandDevice(
                            device['id'] as String,
                            'previous',
                          ),
                        ),
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      IconButton(
                        tooltip: wt('native.6dd5de06c7', context: context),
                        onPressed: () => run(
                          c,
                          () => c.commandDevice(
                            device['id'] as String,
                            object(device['state'])['playing'] == true
                                ? 'pause'
                                : 'play',
                          ),
                        ),
                        icon: Icon(
                          object(device['state'])['playing'] == true
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: wt('native.ca8ab6965b', context: context),
                        onPressed: () => run(
                          c,
                          () => c.commandDevice(device['id'] as String, 'next'),
                        ),
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                      Expanded(
                        child: Slider(
                          value: number(
                            object(device['state'])['volume'],
                            .8,
                          ).clamp(0, 1),
                          onChanged: (v) => run(
                            c,
                            () => c.commandDevice(
                              device['id'] as String,
                              'volume',
                              {'volume': v},
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        clock(number(object(device['state'])['position'])),
                        style: TextStyle(
                          color: waveVisuals(context).muted,
                          fontSize: 11,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: number(object(device['state'])['position'])
                              .clamp(
                                0,
                                (c
                                                .track(
                                                  object(
                                                        device['state'],
                                                      )['trackId']
                                                      as String?,
                                                )
                                                ?.duration ??
                                            0) >
                                        0
                                    ? c
                                          .track(
                                            object(device['state'])['trackId']
                                                as String?,
                                          )!
                                          .duration
                                    : 1,
                              ),
                          max:
                              (c
                                          .track(
                                            object(device['state'])['trackId']
                                                as String?,
                                          )
                                          ?.duration ??
                                      0) >
                                  0
                              ? c
                                    .track(
                                      object(device['state'])['trackId']
                                          as String?,
                                    )!
                                    .duration
                              : 1,
                          onChanged: (v) => run(
                            c,
                            () => c.commandDevice(
                              device['id'] as String,
                              'seek',
                              {'position': v},
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      if (c.devices.isEmpty)
        EmptyState(
          wt('native.76bdd0e417', context: context),
          wt('native.bf9b9e0034', context: context),
          icon: Icons.devices_rounded,
        ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (Platform.isWindows)
            OutlinedButton.icon(
              onPressed: () => showQrLogin(context, c),
              icon: const Icon(Icons.qr_code_rounded),
              label: Text(wt('native.e305e5f150', context: context)),
            ),
          if (Platform.isAndroid || Platform.isIOS)
            OutlinedButton.icon(
              onPressed: scanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(wt('native.280e0f673d', context: context)),
            ),
          TextButton.icon(
            onPressed: discover,
            icon: const Icon(Icons.wifi_find_rounded),
            label: Text(wt('native.8db44b4616', context: context)),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        wt('native.0e89a07236', context: context),
        style: TextStyle(
          color: waveVisuals(context).muted,
          height: 1.7,
          fontSize: 12,
        ),
      ),
    ],
  );
  Future<void> discover() async {
    await run(c, () async {
      final servers = await discoverServers(
        port: (object(c.config['lan'])['discoveryPort'] as int?) ?? 4001,
      );
      if (!mounted) return;
      final value = await showWaveDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: Text(wt('native.f09e6c35a1', context: context)),
          children: [
            for (final server in servers)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, server['url']),
                child: Text(server['url'] as String),
              ),
            if (servers.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text(wt('native.f1d32f86b2', context: context)),
              ),
          ],
        ),
      );
      if (value != null) await c.setServer(value);
    });
  }

  Future<void> scanQr() async {
    String? value;
    if (Platform.isAndroid || Platform.isIOS) {
      value = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const QrScannerPage()),
      );
    } else {
      value = await askText(
        context,
        wt('native.280e0f673d', context: context),
        wt('native.5a257ddf16', context: context),
      );
    }
    if (value == null || !mounted) return;
    await run(c, () async {
      final info = await c.qrInfo(value!);
      if (!mounted) return;
      final allow = await showWaveDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(wt('native.a94c1d3dbe', context: context)),
          content: Text(
            wt(
              'native.ab5de9486a',
              values: {'p0': (info['deviceName'])},
              context: context,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(wt('native.0ec753be8d', context: context)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(wt('native.616bb19d6c', context: context)),
            ),
          ],
        ),
      );
      if (allow == true) await c.approveQr(value);
    });
  }

  Widget profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        wt('native.3c11e25735', context: context),
        wt('native.bd8bfe25b5', context: context),
        eyebrow: wt('native.29352daac4', context: context),
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(waveRadius(context, 24)),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  height: 180,
                  width: double.infinity,
                  color: waveVisuals(context).accentSoft,
                  child: c.user!.banner.isEmpty
                      ? RepaintBoundary(
                          child: CustomPaint(
                            painter: WavePainter(
                              .22,
                              accentColor: waveVisuals(context).accent,
                              style: waveVisuals(context).waveStyle,
                            ),
                          ),
                        )
                      : Image.network(
                          c.api.url(c.user!.banner),
                          fit: BoxFit.cover,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: IconButton.filled(
                    tooltip: wt('native.3288466d0d', context: context),
                    onPressed: () => run(c, () => c.uploadProfile('banner')),
                    icon: const Icon(Icons.photo_outlined, size: 19),
                  ),
                ),
              ],
            ),
            Container(
              color: waveVisuals(context).surface,
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        onTap: () => run(c, () => c.uploadProfile('avatar')),
                        borderRadius: BorderRadius.circular(
                          waveRadius(context, 30),
                        ),
                        child: c.user!.avatar.isNotEmpty
                            ? Artwork(
                                controller: c,
                                url: c.user!.avatar,
                                size: 70,
                                radius: 24,
                              )
                            : Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: waveVisuals(context).accentSoft,
                                  borderRadius: BorderRadius.circular(
                                    waveRadius(context, 24),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 27,
                                ),
                              ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.user!.displayName,
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.6,
                              ),
                            ),
                            Text(
                              '@${c.user!.username}',
                              style: TextStyle(
                                color: waveVisuals(context).muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(
                          c.user!.plan == 'beta'
                              ? 'β BETA'
                              : c.user!.plan == 'unbound'
                              ? 'UNBOUND'
                              : 'FREE',
                        ),
                        backgroundColor: waveVisuals(context).accentSoft,
                        side: BorderSide.none,
                        labelStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (c.user!.bio.isNotEmpty)
                    Text(c.user!.bio, style: const TextStyle(height: 1.7)),
                  if (c.user!.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in c.user!.tags)
                            Chip(
                              label: Text(tag),
                              side: BorderSide(
                                color: waveVisuals(context).line,
                              ),
                              labelStyle: const TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: editProfile,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: Text(wt('native.dd5a0b517a', context: context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: () => navigate(WavePage.settings),
            icon: const Icon(Icons.tune_rounded),
            label: Text(wt('native.7f17c7c62a', context: context)),
          ),
          OutlinedButton.icon(
            onPressed: () => navigate(WavePage.sources),
            icon: const Icon(Icons.hub_outlined),
            label: Text(wt('native.5384db72a4', context: context)),
          ),
          OutlinedButton.icon(
            onPressed: () => navigate(WavePage.downloads),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: Text(wt('native.212ccf5938', context: context)),
          ),
          OutlinedButton.icon(
            onPressed: () => navigate(WavePage.devices),
            icon: const Icon(Icons.devices_rounded),
            label: Text(wt('native.7ab03d602e', context: context)),
          ),
          TextButton(
            onPressed: () => run(c, c.logout),
            child: Text(wt('native.026abb1e0a', context: context)),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wt('native.a61f7c97a6', context: context),
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              c.user!.plan == 'beta'
                  ? wt('native.ae23547099', context: context)
                  : c.user!.plan == 'unbound'
                  ? wt('native.f6da905d33', context: context)
                  : wt('native.02da34d36b', context: context),
              style: TextStyle(
                color: waveVisuals(context).muted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: object(c.config['billing'])['configured'] == true
                  ? () => run(c, () async {
                      final response = await c.api.call(
                        c.user!.plan == 'unbound'
                            ? '/api/billing/portal'
                            : '/api/billing/checkout',
                        method: 'POST',
                        data: {},
                      );
                      await c.openUrl(response['url'] as String);
                      c.tell(wt('native.ec812a93fb'));
                    })
                  : null,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(
                object(c.config['billing'])['configured'] == true
                    ? c.user!.plan == 'unbound'
                          ? wt('native.f545f066e3', context: context)
                          : wt('native.52acff18e2', context: context)
                    : wt('native.f7b2846451', context: context),
              ),
            ),
          ],
        ),
      ),
      section(wt('native.b7eea7b75e', context: context)),
      if (c.playlists.isNotEmpty)
        playlistGrid()
      else
        Text(
          wt('native.dee6918f7b', context: context),
          style: TextStyle(color: waveVisuals(context).muted),
        ),
    ],
  );
  Future<void> editProfile() async {
    final name = TextEditingController(text: c.user!.displayName),
        username = TextEditingController(text: c.user!.username),
        bio = TextEditingController(text: c.user!.bio),
        tags = TextEditingController(text: c.user!.tags.join(', '));
    await showWaveDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(wt('native.ec1641f67e', context: context)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: wt('native.aee78fe860', context: context),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: username,
                  maxLength: 32,
                  decoration: InputDecoration(
                    labelText: wt('native.db0d5a3cc6', context: context),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bio,
                  maxLines: 3,
                  maxLength: 600,
                  decoration: InputDecoration(
                    labelText: wt('native.312416bd6b', context: context),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tags,
                  maxLength: 180,
                  decoration: InputDecoration(
                    labelText: wt('native.d8203fae6b', context: context),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(wt('native.f6dab074d7', context: context)),
          ),
          FilledButton(
            onPressed: () async {
              await run(c, () async {
                await c.updateProfile({
                  'displayName': name.text.trim(),
                  'username': username.text.trim(),
                  'bio': bio.text.trim(),
                  'tags': tags.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                });
                if (dialog.mounted) Navigator.pop(dialog);
              });
            },
            child: Text(wt('native.4864057d62', context: context)),
          ),
        ],
      ),
    );
    name.dispose();
    username.dispose();
    bio.dispose();
    tags.dispose();
  }

  Map<String, (String, IconData)> get settingsSections =>
      <String, (String, IconData)>{
        'account': (
          wt('native.5b16fcdd97', context: context),
          Icons.person_outline_rounded,
        ),
        'appearance': (
          wt('native.d206f1bed0', context: context),
          Icons.palette_outlined,
        ),
        'playback': (
          wt('native.5dcbecbd1a', context: context),
          Icons.graphic_eq_rounded,
        ),
        'storage': (
          wt('native.212ccf5938', context: context),
          Icons.download_for_offline_outlined,
        ),
        'connections': (
          wt('native.c188eb08a1', context: context),
          Icons.hub_outlined,
        ),
        'notifications': (
          wt('native.ee3c35f311', context: context),
          Icons.notifications_none_rounded,
        ),
        'devices': (
          wt('native.7ab03d602e', context: context),
          Icons.devices_rounded,
        ),
        'hotkeys': (
          wt('native.0ad272ade8', context: context),
          Icons.keyboard_outlined,
        ),
        'about': (
          wt('native.b9c9ff652d', context: context),
          Icons.info_outline_rounded,
        ),
      };

  Widget settingsPage() {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final v = waveVisuals(context);
    Widget link(MapEntry<String, (String, IconData)> item) => Semantics(
      selected: settingsSection == item.key,
      child: Material(
        color: settingsSection == item.key ? v.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(v.corners(10)),
        child: InkWell(
          key: Key('settings-${item.key}'),
          borderRadius: BorderRadius.circular(v.corners(10)),
          onTap: () => setState(() => settingsSection = item.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              mainAxisSize: desktop ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(
                  item.value.$2,
                  size: 18,
                  color: settingsSection == item.key ? v.ink : v.muted,
                ),
                const SizedBox(width: 10),
                Text(
                  item.value.$1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: settingsSection == item.key
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: settingsSection == item.key ? v.ink : v.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final detail = SingleChildScrollView(
      key: ValueKey('settings-detail-$settingsSection'),
      padding: const EdgeInsets.only(bottom: 28),
      child: settingsDetail(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          wt('native.ed3fb91811', context: context),
          wt('native.413b6b6e1c', context: context),
          eyebrow: wt('native.aff68c53a5', context: context),
        ),
        if (!desktop) ...[
          SingleChildScrollView(
            key: const Key('settings-navigation'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in settingsSections.entries) link(item),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        Expanded(
          child: desktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 180,
                      child: ListView(
                        children: [
                          for (final item in settingsSections.entries)
                            link(item),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(child: detail),
                  ],
                )
              : detail,
        ),
      ],
    );
  }

  Widget settingsDetail() {
    final v = waveVisuals(context), appearance = c.customization.appearance;
    return switch (settingsSection) {
      'appearance' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.appearanceStore != null)
            AppearanceEntry(store: c.appearanceStore!),
          const SizedBox(height: 18),
          Surface(
            child: settingSwitch(
              wt('native.9e54439649', context: context),
              wt('native.026a78998b', context: context),
              'reducedMotion',
            ),
          ),
        ],
      ),
      'playback' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EqualizerPanel(controller: c),
          const SizedBox(height: 18),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                settingSwitch(
                  wt('native.f296708154', context: context),
                  wt('native.9c1a4954e3', context: context),
                  'lyrics',
                ),
                const Divider(height: 32),
                SwitchListTile(
                  key: const Key('settings-cover-3d'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(wt('native.2988f5fbfc', context: context)),
                  subtitle: Text(wt('native.1228a8a0aa', context: context)),
                  value: appearance.cover3d,
                  onChanged: (value) => run(
                    c,
                    () => c.customize({
                      'appearance': {'cover3d': value},
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final item in {
                      'vinyl': wt('native.8c021dafec', context: context),
                      'cd': 'CD',
                    }.entries)
                      ChoiceChip(
                        key: Key('settings-cover-${item.key}'),
                        label: Text(item.value),
                        selected: appearance.coverKind == item.key,
                        onSelected: (_) => run(
                          c,
                          () => c.customize({
                            'appearance': {'coverKind': item.key},
                          }),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  wt('native.5a01c28561', context: context),
                  style: TextStyle(color: v.muted, fontSize: 12, height: 1.7),
                ),
                if (Platform.isWindows) ...[
                  const Divider(height: 32),
                  OutlinedButton.icon(
                    onPressed: () => run(c, c.desktop.toggleMini),
                    icon: const Icon(
                      Icons.picture_in_picture_alt_rounded,
                      size: 18,
                    ),
                    label: Text(wt('native.ec09cf02cb', context: context)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      'storage' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                settingSwitch(
                  wt('native.b66c3826b6', context: context),
                  wt('native.b970e0b709', context: context),
                  'autoCache',
                ),
                const Divider(height: 32),
                Text(
                  wt('native.cf979a3886', context: context),
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  wt(
                    'native.66a51f90fa',
                    values: {
                      'p0': localizedNumber(
                        c.cache.bytes / (1024 * 1024),
                        decimalDigits: 1,
                        context: context,
                      ),
                    },
                    context: context,
                  ),
                  style: TextStyle(color: v.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: const Key('settings-cache-limit'),
                  initialValue:
                      [256, 512, 1024, 2048, 4096].contains(c.cache.limitMB)
                      ? c.cache.limitMB
                      : 1024,
                  decoration: InputDecoration(
                    labelText: wt('native.4ce03a61f3', context: context),
                  ),
                  items: [256, 512, 1024, 2048, 4096]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            wt(
                              'native.3fac5a808d',
                              values: {'p0': (value)},
                              context: context,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: c.online
                      ? (value) {
                          if (value != null) {
                            run(
                              c,
                              () => c.updateSettings({'cacheLimitMB': value}),
                            );
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: c.cache.entries.isEmpty
                      ? null
                      : () => run(c, () => c.cache.clear()),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                  label: Text(wt('native.cfe7094211', context: context)),
                ),
                const SizedBox(height: 8),
                Text(
                  wt('native.92818e37d4', context: context),
                  style: TextStyle(color: v.muted, fontSize: 11, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          downloads(),
        ],
      ),
      'connections' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sourcesPage(),
          const SizedBox(height: 20),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                settingSwitch(
                  'Discord Rich Presence',
                  Platform.isWindows
                      ? c.discord.status
                      : wt('native.f73970e14f', context: context),
                  'discordPresence',
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed:
                      c.online &&
                          c.integrations.any(
                            (entry) =>
                                entry['provider'] == 'discord' &&
                                entry['configured'] == true,
                          )
                      ? () => run(c, () => c.connectProvider('discord'))
                      : null,
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: Text(wt('native.2b03969a67', context: context)),
                ),
                if (Platform.isWindows) ...[
                  TextButton(
                    onPressed:
                        (object(c.config['discord'])['clientId'] as String? ??
                                '')
                            .isEmpty
                        ? null
                        : () => run(
                            c,
                            () => c.discord.connect(
                              object(c.config['discord'])['clientId'] as String,
                            ),
                          ),
                    child: Text(wt('native.576be5b21a', context: context)),
                  ),
                  const Divider(height: 32),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(wt('native.d9b1f7556f', context: context)),
                    subtitle: Text(wt('native.27b6476a48', context: context)),
                    value: c.presenceBridge.enabled,
                    onChanged: (value) =>
                        run(c, () => c.togglePresenceBridge(value)),
                  ),
                  if (c.presenceBridge.enabled) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      c.bridgePairing,
                      style: TextStyle(color: v.muted, fontSize: 11),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c.bridgePairing));
                        c.tell(wt('native.296b28d576', context: context));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: Text(wt('native.bc56422bc2', context: context)),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
      'notifications' => Surface(
        child: SwitchListTile(
          key: const Key('settings-push'),
          contentPadding: EdgeInsets.zero,
          title: Text(wt('native.d77ccea399', context: context)),
          subtitle: Text(
            c.push.configured && object(c.config['push'])['fcmEnabled'] == true
                ? wt('native.c16c202873', context: context)
                : wt('native.bcec42f75c', context: context),
          ),
          value: c.settings['notifications'] == true,
          onChanged:
              c.online &&
                  c.push.configured &&
                  object(c.config['push'])['fcmEnabled'] == true
              ? (value) => run(c, () => c.enablePush(value))
              : null,
        ),
      ),
      'devices' => devicesPage(),
      'hotkeys' => Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('settings-hotkeys-toggle'),
              contentPadding: EdgeInsets.zero,
              title: Text(wt('native.61b20696ac', context: context)),
              subtitle: Text(wt('native.06c1a8eda7', context: context)),
              value: c.preferences.getBool('nativeHotkeys') ?? true,
              onChanged: (value) async {
                await c.preferences.setBool('nativeHotkeys', value);
                if (mounted) setState(() {});
              },
            ),
            const Divider(height: 30),
            for (final item in {
              wt('native.4a0edcd188', context: context): wt(
                'native.f974582a9e',
                context: context,
              ),
              'Ctrl + →': wt('native.c97fa8b29b', context: context),
              'Ctrl + ←': wt('native.8e1abb9475', context: context),
              'Ctrl + F': wt('native.8396e265bd', context: context),
              'Esc': wt('native.ddaa07f2d9', context: context),
            }.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 95,
                      child: Text(
                        item.key,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.value,
                        style: TextStyle(color: v.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      'about' => Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Brand(),
            const SizedBox(height: 18),
            Text(
              wt('native.63ca392a3c', context: context),
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              wt('native.97639011ba', context: context),
              style: TextStyle(color: v.muted, height: 1.7, fontSize: 12),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'GlukWave',
                applicationVersion: '1.0.0',
              ),
              icon: const Icon(Icons.description_outlined, size: 17),
              label: Text(wt('native.488dd14a85', context: context)),
            ),
            if (c.user?.admin == true) ...[
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_outlined),
                title: Text(wt('native.917e05143a', context: context)),
                subtitle: Text(
                  c.api.server,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => editServer(context, c),
              ),
            ],
          ],
        ),
      ),
      _ => Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Artwork(
                  controller: c,
                  url: c.user!.avatar,
                  size: 52,
                  radius: 26,
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.user!.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        '@${c.user!.username}',
                        style: TextStyle(color: v.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              c.user!.email,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              c.user!.json['emailVerified'] == true
                  ? wt('native.99544f70c8', context: context)
                  : wt('native.457b27490d', context: context),
              style: TextStyle(color: v.muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: editProfile,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(wt('native.0755f11f12', context: context)),
                ),
                TextButton(
                  onPressed: () => navigate(WavePage.profile),
                  child: Text(wt('native.746716f000', context: context)),
                ),
              ],
            ),
            const Divider(height: 36),
            TextButton(
              onPressed: () => run(c, c.logout),
              child: Text(wt('native.1d5ad05dcb', context: context)),
            ),
          ],
        ),
      ),
    };
  }

  Widget settingSwitch(String title, String subtitle, String key) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: waveVisuals(context).muted,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Switch(
        value: c.settings[key] == true,
        onChanged: key == 'reducedMotion'
            ? (v) => run(c, () => c.customize({key: v}))
            : c.online
            ? (v) => run(c, () => c.updateSettings({key: v}))
            : null,
      ),
    ],
  );
}

String providerName(String id) => switch (id) {
  'youtube' => 'YouTube Music',
  'spotify' => 'Spotify',
  'soundcloud' => 'SoundCloud',
  'yandex' => wt('native.0fb8bc0888'),
  'discord' => 'Discord',
  _ => id,
};
IconData sourceIcon(String id) => switch (id) {
  'youtube' => Icons.play_circle_outline_rounded,
  'spotify' => Icons.multitrack_audio_rounded,
  'soundcloud' => Icons.cloud_outlined,
  'yandex' => Icons.auto_awesome_outlined,
  _ => Icons.hub_outlined,
};
Color providerColor(String id) => switch (id) {
  'youtube' => const Color(0xffc96051),
  'spotify' => const Color(0xff44745d),
  'soundcloud' => const Color(0xffdf8350),
  'yandex' => const Color(0xffa9822c),
  _ => accent,
};

Future<void> showQrLogin(BuildContext context, WaveController c) async {
  await run(c, () async {
    final qr = await c.api.call(
      '/api/auth/qr',
      method: 'POST',
      data: {'deviceName': c.deviceName},
    );
    if (!context.mounted) return;
    await showWaveDialog<void>(
      context: context,
      builder: (_) => QrLoginDialog(controller: c, qr: qr),
    );
  });
}

class QrLoginDialog extends StatefulWidget {
  final WaveController controller;
  final Json qr;
  const QrLoginDialog({super.key, required this.controller, required this.qr});
  @override
  State<QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<QrLoginDialog> {
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(wait());
  }

  Future<void> wait() async {
    try {
      await widget.controller.pollSession(
        '/api/auth/qr/${widget.qr['id']}',
        widget.qr['secret'] as String,
        challengeExpiry(widget.qr['expiresAt']),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    widget.controller.cancelAuth = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(wt('native.2b9ecdfc9d', context: context)),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: widget.qr['url'] as String,
            size: 230,
            backgroundColor: waveVisuals(context).surface,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: waveVisuals(context).ink,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: waveVisuals(context).ink,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            wt('native.5156e365fc', context: context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: waveVisuals(context).muted,
              height: 1.7,
              fontSize: 12,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xffa44f40)),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(wt('native.4ae50d3073', context: context)),
      ),
    ],
  );
}

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool found = false;
  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: waveVisuals(context).background,
      title: Text(wt('native.280e0f673d', context: context)),
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: scanner,
          onDetect: (capture) {
            if (found) return;
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value == null) return;
            found = true;
            Navigator.pop(context, value);
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              wt('native.c3badea7fc', context: context),
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
      ],
    ),
  );
}

class AdminPage extends StatefulWidget {
  final WaveController controller;
  const AdminPage({super.key, required this.controller});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Json data = {};
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final result = await widget.controller.api.call('/api/admin/overview');
      if (mounted) setState(() => data = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        wt('native.8182fca7f7', context: context),
        wt('native.850de99e1e', context: context),
        eyebrow: wt('native.a8ce65c8da', context: context),
      ),
      if (error != null)
        Text(error!)
      else if (data.isEmpty)
        CircularProgressIndicator(color: waveVisuals(context).accent)
      else ...[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in object(data['counts']).entries)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.value.toString(),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: waveVisuals(context).accent,
                      ),
                    ),
                    Text(
                      entry.key,
                      style: TextStyle(
                        color: waveVisuals(context).muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        for (final user in objects(data['users']))
          ListTile(
            title: Text(
              user['displayName'] as String? ??
                  user['username'] as String? ??
                  '',
            ),
            subtitle: Text(user['email'] as String? ?? ''),
            trailing: DropdownButton<String>(
              value: user['plan'] as String? ?? 'free',
              items: ['free', 'beta', 'unbound']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => run(widget.controller, () async {
                await widget.controller.api.call(
                  '/api/admin/users/${user['id']}',
                  method: 'PATCH',
                  data: {'plan': value},
                );
                await load();
              }),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          wt('native.2355a3badd', context: context),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        for (final event in objects(data['events']).take(30))
          ListTile(
            leading: const Icon(Icons.terminal_rounded, size: 19),
            title: Text(
              event['type'] as String? ??
                  event['action'] as String? ??
                  wt('native.bb92633bf5', context: context),
            ),
            subtitle: Text(
              event['createdAt'] as String? ?? '',
              style: TextStyle(fontSize: 11, color: waveVisuals(context).muted),
            ),
          ),
      ],
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: load,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(wt('native.c2f668e54f', context: context)),
      ),
    ],
  );
}
