import 'recommendation_actions.dart';
import '../l10n/glukwave27_ui_strings.dart';
import 'home_canvas.dart';
import 'update_notice.dart';
import 'desktop_titlebar.dart';
import 'playlist_manager.dart';
import 'playlist_strings.dart';
import 'library_sort.dart';
import '../core/library_order.dart';
import 'wave18_strings.dart';
import 'provider_import.dart';
import 'public_import_strings.dart';
import 'refinement20_strings.dart';
import 'native19_strings.dart';
import 'native19_components.dart';
import 'native19_saved.dart';
import 'native19_guard.dart';
import 'room_directory.dart';
import 'listening_presence.dart';
import '../l10n/ecosystem_polish_strings.dart';
import 'motion_icons.dart';
import 'discovery.dart';
import '../l10n/listening_polish_strings.dart';
import 'cover_accent.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/controller.dart';
import '../core/appearance.dart';
import '../core/parity.dart';
import '../l10n/parity_strings.dart';
import 'parity_panels.dart';
import '../core/models.dart';
import 'equalizer_panel.dart';
import '../services/desktop.dart';
import 'widgets.dart';
import 'player.dart';
import 'appearance_panel.dart';
import 'seasonal.dart';
import 'auth_visuals.dart';
import 'auth_page.dart';
import 'top_notice.dart';
import '../l10n/glukwave26_strings.dart';
export 'auth_page.dart' show AuthPage;
import 'desktop_player.dart';
import 'connect_panel.dart';
import 'discord_panel.dart';
import 'sessions_panel.dart';
import 'device_labels.dart';
import 'listening_rail.dart';
import 'lofi.dart';
import '../l10n/wave_localizations.dart';
import '../l10n/home_widget_strings.dart';
import 'home_widget_previews.dart';

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
  friends,
  artists,
  discover,
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
  ptLabel('Friends'),
  ptLabel('Artists'),
  ptLabel('Discover playlists'),
];
String ptLabel(String key) => parityLabel(WaveStrings.current.language, key);
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
  Icons.settings_rounded,
  Icons.terminal_rounded,
  Icons.people_outline_rounded,
  Icons.album_outlined,
  Icons.explore_outlined,
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
  String? _noticeText, _lastNoticeText;
  DateTime? _noticeAt;
  Timer? _noticeTimer;
  bool _foreground = true;
  WaveCustomization? _customization;
  ThemeData? _light, _dark;
  final _coverSampler = CoverAccentSampler();
  String? _coverKey;
  Color? _coverAccent, _themeAccent;
  bool _highContrast = false;
  bool _energySaving = false;
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

  @override
  void didChangePlatformBrightness() {
    widget.controller.refreshHomeWidgetAppearance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    widget.controller.setVisualForeground(foreground);
    if (mounted && _foreground != foreground) {
      setState(() => _foreground = foreground);
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.applicationResumed());
    }
  }

  void _refreshCover() {
    final c = widget.controller, track = c.audio.viewCurrent;
    final key =
        '${c.user?.id}:${track?.id}:${track?.artwork}:${c.cache.artworkForUrl(track?.artwork ?? '')}:${c.online}:${c.energySaving}:${c.customization.appearance.coverAccent}';
    if (key == _coverKey) return;
    _coverKey = key;
    _coverSampler.cancel();
    if (c.energySaving) return;
    if (!c.customization.appearance.coverAccent ||
        track == null ||
        track.artwork.isEmpty) {
      _coverAccent = null;
      return;
    }
    final provider = waveArtworkProvider(c, track.artwork);
    if (provider == null) return;
    _coverSampler.read(key, provider, (tone) {
      if (!mounted || _coverKey != key) return;
      setState(() => _coverAccent = tone);
    });
  }

  void _changed() {
    _refreshCover();
    final c = widget.controller;
    if (c.noticeRevision == _notice || c.notice == null) return;
    _notice = c.noticeRevision;
    final text = c.notice!;
    final now = DateTime.now();
    if (_lastNoticeText == text &&
        _noticeAt != null &&
        now.difference(_noticeAt!).inSeconds < 3) {
      return;
    }
    _lastNoticeText = text;
    _noticeAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _noticeTimer?.cancel();
      setState(() {
        _noticeText = text;
        _noticeAt = now;
      });
      _noticeTimer = Timer(Duration(seconds: text.length > 100 ? 7 : 4), () {
        if (mounted) setState(() => _noticeText = null);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    _coverSampler.dispose();
    _noticeTimer?.cancel();
    timeDilation = 1;
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, child) {
      final c = widget.controller, customization = c.customization;
      final highContrast = WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .highContrast;
      _refreshCover();
      if (!identical(_customization, customization) ||
          _themeAccent != _coverAccent ||
          _energySaving != c.energySaving ||
          _highContrast != highContrast) {
        _energySaving = c.energySaving;
        _highContrast = highContrast;
        _themeAccent = _coverAccent;
        _customization = customization;
        _light = buildWaveTheme(
          customization,
          Brightness.light,
          coverAccent: _coverAccent,
          highContrast: highContrast,
        );
        _dark = buildWaveTheme(
          customization,
          Brightness.dark,
          coverAccent: _coverAccent,
          highContrast: highContrast,
        );
        if (c.energySaving) {
          ThemeData lighter(ThemeData theme) => theme.copyWith(
            extensions: [
              theme.extension<WaveVisuals>()!.copyWith(
                reducedMotion: true,
                blur: false,
              ),
            ],
          );
          _light = lighter(_light!);
          _dark = lighter(_dark!);
        }
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
            : const Duration(milliseconds: 900),
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messenger,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.textScalerOf(context).scale(1) *
                  customization.fontScale,
            ),
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) ||
                c.energySaving ||
                customization.reducedMotion,
          ),
          child: TickerMode(
            enabled: _foreground,
            child: Stack(
              children: [
                child!,
                if (_noticeText != null)
                  WaveTopNotice(
                    text: _noticeText!,
                    onClose: () {
                      _noticeTimer?.cancel();
                      setState(() => _noticeText = null);
                    },
                  ),
              ],
            ),
          ),
        ),
        home: Builder(
          builder: (context) {
            if (c.restoringLocal || c.loading && c.user == null) {
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
  String filter = 'all', source = 'all', searchType = 'all';
  Json? selectedPlaylist;
  final search = TextEditingController(), chat = TextEditingController();
  final searchFocus = FocusNode();
  Timer? _searchTimer;
  bool searching = false;
  late final playerReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  final miniArtwork = GlobalKey(), fullArtwork = GlobalKey();
  bool playerVisible = false;
  WaveTrack? previewTrack;
  int playerInitialTab = 0;
  Rect? coverOrigin, coverDestination;
  double dragOrigin = 0;
  int playerTransition = 0;
  int searchRequest = 0;
  String settingsSection = 'account';
  final settingsSearch = TextEditingController();
  String settingsQuery = '';
  late final WaveParity parity = WaveParity(c.api);
  String mood = 'personal', waveMode = 'personal';
  bool waveStarting = false;
  String? waveStartError, _seenWaveSelection;
  void waveSelectionChanged() {
    if (!c.waveActive) {
      _seenWaveSelection = null;
      return;
    }
    final selected = '${c.waveMode}:${c.waveMood}';
    if (selected == _seenWaveSelection) {
      return;
    }
    _seenWaveSelection = selected;
    if (mounted) {
      setState(() {
        waveMode = c.waveMode;
        mood = c.waveMood;
      });
    }
  }

  io.Socket? paritySocket;
  void friendsChanged(dynamic _) => unawaited(parity.refreshFriends());
  void tasteChanged(dynamic _) => unawaited(parity.refreshTaste());
  void attachParitySocket() {
    if (identical(paritySocket, c.socket)) return;
    paritySocket?.off('friends:changed', friendsChanged);
    paritySocket?.off('taste:changed', tasteChanged);
    paritySocket = c.socket;
    paritySocket?.on('friends:changed', friendsChanged);
    paritySocket?.on('taste:changed', tasteChanged);
  }

  void parityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Compact desktop modes do not otherwise touch the full player animation.
    // Create its ticker while this State is alive, before dispose can run.
    playerReveal;
    parity.addListener(parityChanged);
    c.addListener(waveSelectionChanged);
    waveSelectionChanged();
    attachParitySocket();
    unawaited(parity.load(mood: mood, mode: waveMode));
  }

  @override
  void dispose() {
    search.dispose();
    settingsSearch.dispose();
    searchFocus.dispose();
    chat.dispose();
    _searchTimer?.cancel();
    playerReveal.dispose();
    c.removeListener(waveSelectionChanged);
    parity.removeListener(parityChanged);
    parity.dispose();
    paritySocket?.off('friends:changed', friendsChanged);
    paritySocket?.off('taste:changed', tasteChanged);
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
    attachParitySocket();
    if (c.desktop.mini || c.desktop.quick) {
      return DesktopCompactPlayer(controller: c, quick: c.desktop.quick);
    }
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final shell = Scaffold(
      appBar: DesktopTitleBar.supported
          ? PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: DesktopTitleBar(controller: c),
            )
          : null,
      body: SafeArea(
        child: SeasonalBackdrop(
          settings: c.customization.seasonalEffects,
          child: Row(
            children: [
              if (desktop) sidebar(),
              Expanded(
                child: Column(
                  children: [
                    topbar(desktop),
                    WaveUpdateNotice(controller: c),
                    if (c.room != null) roomPin(),
                    if (!c.online)
                      NativeOfflineNotice(
                        onSaved: () => navigate(WavePage.downloads),
                        onRetry: () => run(c, c.refresh),
                      )
                    else if (c.error != null)
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
                      child: Row(
                        children: [
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
                                      milliseconds:
                                          c.settings['reducedMotion'] == true
                                          ? 0
                                          : 220,
                                    ),
                                    child: SingleChildScrollView(
                                      key: ValueKey(
                                        '$page:${selectedPlaylist?['id']}',
                                      ),
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
                          if (MediaQuery.sizeOf(context).width >= 1560 &&
                              [
                                WavePage.home,
                                WavePage.library,
                                WavePage.search,
                                WavePage.liked,
                              ].contains(page))
                            DesktopListeningRail(
                              controller: c,
                              onExpand: () => showPlayer(),
                              onQueue: () => showPlayer(tab: 2),
                              onDevices: () => navigate(WavePage.devices),
                            ),
                        ],
                      ),
                    ),
                    if (c.audio.viewCurrent != null)
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
                          onDevices: () => navigate(WavePage.devices),
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
            final shift = (1 - extent) * MediaQuery.sizeOf(context).height;
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
                      color: Colors.black.withValues(alpha: .5 * extent),
                    ),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: (extent * 2.5).clamp(0, 1),
                      child: Transform.translate(
                        offset: Offset(0, shift),
                        child: Material(
                          key: const Key('full-player'),
                          color: waveVisuals(context).background,
                          child: SafeArea(
                            child: PlayerPage(
                              controller: c,
                              initialTrack: previewTrack,
                              initialTab: playerInitialTab,
                              onMore: more,
                              onClose: () => settlePlayer(false),
                              onDevices: () {
                                settlePlayer(false);
                                navigate(WavePage.devices);
                              },
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
                      c.audio.viewCurrent != null)
                    Positioned.fromRect(
                      rect: Rect.lerp(coverOrigin, coverDestination, extent)!,
                      child: IgnorePointer(
                        child: Artwork(
                          key: const Key('player-cover-transition'),
                          controller: c,
                          url: c.audio.viewCurrent!.artwork,
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
    if (playerVisible ||
        (c.audio.viewCurrent == null && previewTrack == null)) {
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
            (1 - playerReveal.value) * MediaQuery.sizeOf(context).height;
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
        c.audio.viewCurrent != null &&
        c.canControl) {
      run(c, c.audio.playing ? c.audio.pause : c.audio.play);
    } else if (control &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        c.canControl) {
      run(c, c.audio.skipToNext);
    } else if (control &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        c.canControl) {
      run(c, c.audio.skipToPrevious);
    } else if (control &&
        (event.logicalKey == LogicalKeyboardKey.keyF ||
            event.logicalKey == LogicalKeyboardKey.keyK) &&
        !playerVisible) {
      navigate(WavePage.search);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) searchFocus.requestFocus();
      });
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget sidebar() => compactSidebar();

  Widget compactSidebar() {
    final v = waveVisuals(context);
    return Container(
      key: const Key('desktop-navigation-rail'),
      width: 84,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: v.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 22),
      child: Column(
        children: [
          Brand(compact: true, size: 38, animated: !v.reducedMotion),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final value in [
                    WavePage.home,
                    WavePage.search,
                    WavePage.library,
                    WavePage.rooms,
                    WavePage.friends,
                    WavePage.sources,
                    WavePage.downloads,
                    WavePage.devices,
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: WavePress(
                        child: IconButton(
                          key: Key('nav-${value.name}'),
                          tooltip: pageLabels[value.index],
                          onPressed: () => navigate(value),
                          isSelected: page == value,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(54, 54),
                            backgroundColor: page == value
                                ? v.accentSoft
                                : Colors.transparent,
                            foregroundColor: page == value ? v.ink : v.muted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                v.corners(16),
                              ),
                            ),
                          ),
                          icon: WaveControlIcon(
                            pageIcons[value.index],
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          WavePress(
            child: IconButton(
              key: const Key('nav-settings'),
              tooltip: pageLabels[WavePage.settings.index],
              onPressed: () => navigate(WavePage.settings),
              icon: const WaveControlIcon(Icons.settings_rounded),
            ),
          ),
          if (c.user?.admin == true)
            IconButton(
              key: const Key('nav-admin'),
              tooltip: pageLabels[WavePage.admin.index],
              onPressed: () => navigate(WavePage.admin),
              icon: const Icon(Icons.terminal_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget topbar(bool desktop) {
    final v = waveVisuals(context),
        tight = MediaQuery.sizeOf(context).width < 360;
    return Container(
      height: desktop ? 78 : 66,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 30 : 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: v.line)),
      ),
      child: Row(
        children: [
          if (!desktop)
            Brand(
              size: 29,
              compact: tight || MediaQuery.textScalerOf(context).scale(1) > 1.1,
              animated: !v.reducedMotion,
            ),
          if (desktop)
            Expanded(
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width < 1100
                          ? 350
                          : 470,
                    ),
                    child: TextField(
                      controller: search,
                      focusNode: searchFocus,
                      decoration: InputDecoration(
                        hintText: wt('native.eaad77f8f4', context: context),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.all(14),
                          child: WaveControlIcon(
                            Icons.search_rounded,
                            size: 19,
                          ),
                        ),
                        suffixIcon: const Center(
                          widthFactor: 1,
                          child: Padding(
                            padding: EdgeInsets.only(right: 14),
                            child: Text(
                              'Ctrl K',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      onChanged: scheduleSearch,
                      onSubmitted: (_) => doSearch(),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            )
          else
            const Spacer(),
          if (!desktop)
            IconButton(
              key: const Key('mobile-guard'),
              tooltip: nativeText(context, 'guard'),
              onPressed: c.online ? () => showWaveGuard(context, c) : null,
              icon: WaveControlIcon(
                Icons.qr_code_scanner_rounded,
                size: 20,
                color: v.muted,
              ),
            ),
          if (!tight || desktop)
            IconButton(
              key: const Key('mobile-rooms'),
              tooltip: wt('native.200ba6b661', context: context),
              onPressed: () => navigate(WavePage.rooms),
              icon: WaveControlIcon(
                Icons.spatial_audio_off_outlined,
                size: 21,
                color: v.muted,
              ),
            ),
          if (desktop)
            IconButton(
              tooltip: wt('native.7ab03d602e', context: context),
              onPressed: () => navigate(WavePage.devices),
              icon: WaveControlIcon(
                Icons.devices_rounded,
                size: 21,
                color: c.controllingRemote ? v.accent : v.muted,
              ),
            ),
          PopupMenuButton<String>(
            key: const Key('mobile-menu'),
            tooltip: nativeText(context, 'more'),
            icon: WaveControlIcon(
              Icons.more_horiz_rounded,
              size: 22,
              color: v.muted,
            ),
            onSelected: (value) {
              if (value == 'guard') {
                showWaveGuard(context, c);
              } else if (value == 'lofi') {
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
              for (final item in <String, (String, IconData)>{
                'downloads': (
                  nativeText(context, 'saved'),
                  Icons.download_for_offline_outlined,
                ),
                'rooms': (
                  wt('native.200ba6b661', context: context),
                  Icons.spatial_audio_off_outlined,
                ),
                'friends': (
                  pt(context, 'Friends'),
                  Icons.people_outline_rounded,
                ),
                'devices': (
                  wt('native.7ab03d602e', context: context),
                  Icons.devices_rounded,
                ),
                'guard': (
                  nativeText(context, 'guard'),
                  Icons.qr_code_scanner_rounded,
                ),
                'artists': (
                  pt(context, 'Artists'),
                  Icons.person_outline_rounded,
                ),
                'discover': (
                  pt(context, 'Discover playlists'),
                  Icons.album_outlined,
                ),
                'lofi': (
                  wt('native.847e19da38', context: context),
                  Icons.nightlight_outlined,
                ),
                'sources': (
                  wt('native.5384db72a4', context: context),
                  Icons.hub_outlined,
                ),
                'settings': (
                  wt('native.7f17c7c62a', context: context),
                  Icons.settings_rounded,
                ),
              }.entries)
                PopupMenuItem(
                  value: item.key,
                  child: Row(
                    children: [
                      WaveControlIcon(item.value.$2, size: 19, color: v.muted),
                      const SizedBox(width: 14),
                      Flexible(child: Text(item.value.$1)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          InkWell(
            key: const Key('profile-link'),
            borderRadius: BorderRadius.circular(v.corners(28)),
            onTap: () => navigate(WavePage.profile),
            child: SizedBox(
              width: 42,
              height: 44,
              child: Center(
                child: c.user?.avatar.isNotEmpty == true
                    ? Artwork(
                        controller: c,
                        url: c.user!.avatar,
                        size: 32,
                        radius: 24,
                      )
                    : Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: v.accentSoft,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: v.accent.withValues(alpha: .45),
                          ),
                        ),
                        child: Text(
                          (c.user?.displayName ?? 'W').characters.first
                              .toUpperCase(),
                          style: TextStyle(
                            color: v.ink,
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
  }

  Widget bottomNavigation() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
    child: Row(
      children: [
        for (final value in [WavePage.home, WavePage.search, WavePage.library])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: WavePress(
                child: InkWell(
                  onTap: () => navigate(value),
                  key: Key('nav-${value.name}'),
                  borderRadius: BorderRadius.circular(waveRadius(context, 19)),
                  child: AnimatedContainer(
                    duration: waveVisuals(context).duration(220),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: page == value
                          ? waveVisuals(context).accentSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        waveRadius(context, 19),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WaveControlIcon(
                          pageIcons[value.index],
                          size: 22,
                          color: page == value
                              ? waveVisuals(context).ink
                              : waveVisuals(context).muted,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          pageLabels[value.index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: page == value
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: page == value
                                ? waveVisuals(context).ink
                                : waveVisuals(context).muted,
                          ),
                        ),
                      ],
                    ),
                  ),
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
        c.savedTracks.isEmpty &&
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
      WavePage.downloads => NativeSavedView(
        controller: c,
        onMore: more,
        onBrowse: () => navigate(WavePage.search),
      ),
      WavePage.devices => devicesPage(),
      WavePage.profile => profile(),
      WavePage.settings => settingsPage(),
      WavePage.admin => AdminPage(controller: c),
      WavePage.friends => FriendsPage(
        controller: c,
        parity: parity,
        onRoom: () => navigate(WavePage.rooms),
      ),
      WavePage.artists => ArtistBrowse(controller: c),
      WavePage.discover => PublicPlaylists(controller: c),
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
  Widget homeTrackRail(List<WaveTrack> items) {
    final v = waveVisuals(context),
        size = MediaQuery.sizeOf(context).width < 700 ? 142.0 : 164.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final track in items)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: SizedBox(
                width: size,
                child: WavePress(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(v.corners(16)),
                    onTap: () => run(c, () => c.play(track, list: items)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Artwork(
                          controller: c,
                          url: track.artwork,
                          size: size,
                          radius: 16,
                        ),
                        const SizedBox(height: 11),
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
                          style: TextStyle(color: v.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget home() {
    final hour = DateTime.now().hour;
    final greeting = hour >= 18
        ? wt('native.37f9f18bdc', context: context)
        : hour >= 12
        ? wt('native.51d822d031', context: context)
        : hour >= 5
        ? wt('native.d73c91bbc4', context: context)
        : wt('native.194858b25f', context: context);
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
        if (!c.online && c.savedTracks.isNotEmpty) ...[
          CollectionDestination(
            key: const Key('home-saved'),
            title: nativeText(context, 'saved'),
            subtitle:
                '${c.savedTracks.length} · ${nativeText(context, 'savedShort')}',
            icon: Icons.download_for_offline_outlined,
            prominent: true,
            onTap: () => navigate(WavePage.downloads),
          ),
          const SizedBox(height: 28),
        ],
        NativeHomeCanvas(
          key: ValueKey('home-canvas:${c.user?.id}:${c.api.server}'),
          controller: c,
          waveBuilder: (_) => homeWave(),
          recommendations: parity.tracks
              .where((t) => t.playable)
              .take(8)
              .toList(),
          recommendationsLoading: parity.loading,
          recommendationsError: parity.error,
          onRetry: () => parity.load(mood: mood, mode: waveMode),
          onLikes: () => navigate(WavePage.liked),
          onCreatePlaylist: newPlaylist,
          onPlaylist: (playlist) => setState(() {
            selectedPlaylist = playlist;
            page = WavePage.library;
          }),
          recommendationFooter: TasteInvitation(
            parity: parity,
            onOpen: () => openTaste(context, c, parity),
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
              constraints: const BoxConstraints(minHeight: 196),
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
                  mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(height: 24),
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

  Widget homeWave() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WaveHero(
        controller: c,
        empty: false,
        loading: waveStarting || c.trackLoading,
        playing:
            c.waveActive &&
            c.waveMode == waveMode &&
            c.waveMood == mood &&
            c.audio.playing,
        caption: wave18Text(context, 'wave18.caption.$waveMode'),
        reducedMotion: c.settings['reducedMotion'] == true,
        onPlay: waveStarting
            ? null
            : () async {
                setState(() {
                  waveStarting = true;
                  waveStartError = null;
                });
                try {
                  if (c.waveActive &&
                      c.waveMode == waveMode &&
                      c.waveMood == mood &&
                      c.audio.viewCurrent != null) {
                    c.audio.playing
                        ? await c.audio.pause()
                        : await c.audio.play();
                  } else {
                    await c.startWave(mood: mood, mode: waveMode);
                  }
                } catch (error) {
                  if (mounted) {
                    setState(() => waveStartError = error.toString());
                  }
                } finally {
                  if (mounted) setState(() => waveStarting = false);
                }
              },
      ),
      const SizedBox(height: 4),
      Text(
        refinementText(
          context,
          c.waveActive && c.waveMode == waveMode && c.waveMood == mood
              ? 'waveContinues'
              : 'waveStartChoice',
        ),
        style: TextStyle(fontSize: 11, color: waveVisuals(context).muted),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final mode in const [
            'personal',
            'favorites',
            'discovery',
            'popular',
          ])
            ChoiceChip(
              key: Key('wave-mode-$mode'),
              showCheckmark: false,
              backgroundColor: Colors.transparent,
              selectedColor: waveVisuals(context).surface,
              side: BorderSide.none,
              elevation: 0,
              pressElevation: 0,
              shadowColor: Colors.transparent,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: waveMode == mode
                    ? waveVisuals(context).ink
                    : waveVisuals(context).muted,
              ),
              label: Text(wave18Text(context, 'wave18.mode.$mode')),
              selected: waveMode == mode,
              onSelected: waveStarting
                  ? null
                  : (_) {
                      setState(() {
                        waveMode = mode;
                        waveStartError = null;
                      });
                      unawaited(parity.load(mood: mood, mode: waveMode));
                    },
            ),
        ],
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final value in const [
              'personal',
              'energy',
              'happy',
              'calm',
              'sad',
              'focus',
              'dream',
            ])
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  key: Key('wave-mood-$value'),
                  showCheckmark: false,
                  backgroundColor: Colors.transparent,
                  selectedColor: waveVisuals(context).surface,
                  side: BorderSide.none,
                  elevation: 0,
                  pressElevation: 0,
                  shadowColor: Colors.transparent,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: mood == value
                        ? waveVisuals(context).ink
                        : waveVisuals(context).muted,
                  ),
                  label: Text(wave18Text(context, 'wave18.mood.$value')),
                  selected: mood == value,
                  onSelected: waveStarting
                      ? null
                      : (_) {
                          setState(() {
                            mood = value;
                            waveStartError = null;
                          });
                          unawaited(parity.load(mood: mood, mode: waveMode));
                        },
                ),
              ),
          ],
        ),
      ),
      if (waveStartError != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            waveStartError!,
            style: TextStyle(color: waveVisuals(context).muted, fontSize: 12),
          ),
        ),
      const SizedBox(height: 16),
      if (parity.loading)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (parity.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  pt(context, 'Unavailable detail'),
                  style: TextStyle(
                    color: waveVisuals(context).muted,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => parity.load(mood: mood, mode: waveMode),
                child: Text(pt(context, 'Retry')),
              ),
            ],
          ),
        ),
    ],
  );

  Future<void> newPlaylist() => showPlaylistEditor(context, c);

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
                onTap: playlist['id'].toString().startsWith('pending:')
                    ? null
                    : () => setState(() {
                        selectedPlaylist = playlist;
                        page = WavePage.library;
                      }),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlaylistArtwork(
                      controller: c,
                      playlist: playlist,
                      size: width,
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
                      playlist['id'].toString().startsWith('pending:')
                          ? playlistText(context, 'saving')
                          : playlistText(context, 'tracks', {
                              'count': List.from(
                                playlist['trackIds'] ?? [],
                              ).length,
                            }),
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
    if (selectedPlaylist != null) {
      selectedPlaylist =
          c.playlists
              .where((p) => p['id'] == selectedPlaylist!['id'])
              .firstOrNull ??
          selectedPlaylist;
    }
    var items = [...c.tracks];
    if (liked || filter == 'liked') {
      items = c.likedIds.map(c.track).whereType<WaveTrack>().toList();
    }
    if (filter == 'local' && !liked) {
      items = items.where((t) => t.source == 'local').toList();
    }
    if (selectedPlaylist != null) {
      final ids = List<String>.from(selectedPlaylist!['trackIds'] ?? []);
      items = ids.map(c.track).whereType<WaveTrack>().toList();
    }
    final view = selectedPlaylist == null
        ? (liked ? 'liked' : filter)
        : 'playlist:${selectedPlaylist!['id']}';
    final sortKey = 'librarySort:${c.namespace}:$view',
        sort =
            c.preferences.getString(sortKey) ??
            (selectedPlaylist == null ? 'recent' : 'original');
    final recent = selectedPlaylist != null
        ? byRecentDates(items, object(selectedPlaylist!['trackAddedAt']))
        : liked || filter == 'liked'
        ? items
        : byRecentDates(items, c.addedAt);
    items = sortedTracks(items, sort, recent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedPlaylist == null && !liked) ...[
          CollectionDestination(
            key: const Key('library-saved'),
            title: nativeText(context, 'saved'),
            subtitle:
                '${c.savedTracks.length} · ${nativeText(context, 'savedShort')}',
            icon: Icons.download_for_offline_outlined,
            prominent: true,
            onTap: () => navigate(WavePage.downloads),
          ),
          const SizedBox(height: 22),
        ],
        if (selectedPlaylist != null)
          TextButton.icon(
            onPressed: () => setState(() => selectedPlaylist = null),
            icon: const Icon(Icons.arrow_back, size: 17),
            label: Text(wt('native.082b4a891b', context: context)),
          ),
        if (selectedPlaylist != null)
          PlaylistDetailHeader(
            controller: c,
            playlist: selectedPlaylist!,
            tracks: items,
            onAdd: () => showPlaylistTracks(
              context,
              c,
              selectedPlaylist!['id'].toString(),
            ),
            onEdit: () async {
              await showPlaylistEditor(context, c, playlist: selectedPlaylist);
              if (mounted) {
                setState(() {
                  if (!c.playlists.any(
                    (p) => p['id'] == selectedPlaylist?['id'],
                  )) {
                    selectedPlaylist = null;
                  }
                });
              }
            },
          )
        else
          PageHeading(
            liked
                ? wt('native.d3aa3fa13d', context: context)
                : wt('native.27925da08c', context: context),
            wt('native.9221337472', context: context),
            eyebrow: wt('native.708d386559', context: context),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (!liked && selectedPlaylist == null)
                for (final entry in {
                  'all': wt('native.7b4cc84722', context: context),
                  'playlists': wt('native.5cbd56308f', context: context),
                  'liked': wt('native.d3aa3fa13d', context: context),
                  'local': wt('native.da39e0cc91', context: context),
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: filter == entry.key,
                      onSelected: (_) => setState(() => filter = entry.key),
                      showCheckmark: false,
                    ),
                  ),
              PopupMenuButton<String>(
                tooltip: nativeText(context, 'libraryActions'),
                icon: const WaveControlIcon(Icons.more_horiz_rounded),
                onSelected: (value) {
                  if (value == 'upload') {
                    run(c, c.uploadAudio);
                  } else if (value == 'create') {
                    newPlaylist();
                  } else if (value == 'save') {
                    run(c, () => c.downloadTracks(items));
                  } else {
                    navigate(WavePage.discover);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'create',
                    enabled: c.online,
                    child: Text(wt('native.d6ab7b0b5a', context: context)),
                  ),
                  PopupMenuItem(
                    value: 'upload',
                    enabled: c.online,
                    child: Text(wt('native.99855bf52d', context: context)),
                  ),
                  if (selectedPlaylist != null)
                    PopupMenuItem(
                      value: 'save',
                      enabled: c.online && items.isNotEmpty,
                      child: Text(nativeText(context, 'savePlaylist')),
                    ),
                  PopupMenuItem(
                    value: 'discover',
                    child: Text(pt(context, 'Discover playlists')),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (c.uploadProgress != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: LinearProgressIndicator(
              value: c.uploadProgress,
              color: waveVisuals(context).accent,
            ),
          ),
        if (filter != 'playlists' || selectedPlaylist != null || liked)
          Align(
            alignment: Alignment.centerRight,
            child: LibrarySortControl(
              value: sort,
              playlist: selectedPlaylist != null,
              onChanged: (value) {
                unawaited(c.preferences.setString(sortKey, value));
                setState(() {});
              },
            ),
          ),
        const SizedBox(height: 16),
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
        if (selectedPlaylist != null) ...[
          const SizedBox(height: 24),
          PlaylistPublishing(
            controller: c,
            playlist: selectedPlaylist!,
            onChanged: (value) {
              if (mounted) setState(() => selectedPlaylist = value);
            },
          ),
          const SizedBox(height: 16),
        ],
        if (selectedPlaylist != null && items.isNotEmpty)
          PlaylistOrder(controller: c, id: selectedPlaylist!['id'].toString()),
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
      if (search.text.trim().isEmpty)
        PageHeading(
          polishText('browse', context),
          polishText('browseDetail', context),
          eyebrow: wt('native.9bd84125bc', context: context),
        ),
      if (MediaQuery.sizeOf(context).width < 900)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: TextField(
            key: const Key('discovery-query'),
            controller: search,
            focusNode: searchFocus,
            onChanged: scheduleSearch,
            onSubmitted: (_) => doSearch(),
            decoration: InputDecoration(
              prefixIcon: const Padding(
                padding: EdgeInsets.all(14),
                child: WaveControlIcon(Icons.search_rounded, size: 20),
              ),
              hintText: wt('native.bbd9181561', context: context),
              suffixIcon: IconButton(
                onPressed: doSearch,
                tooltip: wt('native.58212e541c', context: context),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
        ),
      if (c.suggestion != null)
        TextButton(
          onPressed: () {
            search.text = c.suggestion!;
            doSearch();
          },
          child: Text(
            wt(
              'native.f1b3941857',
              values: {'p0': c.suggestion},
              context: context,
            ),
          ),
        ),
      DiscoveryView(
        controller: c,
        query: search.text,
        type: searchType,
        source: source,
        loading: searching,
        onType: (value) => setState(() => searchType = value),
        onSource: (value) {
          setState(() => source = value);
          doSearch();
        },
        onQuery: (value) {
          search.text = value;
          doSearch();
        },
        onPlaylist: (playlist) => openDiscoveryPlaylist(context, c, playlist),
        onMore: more,
      ),
      if (search.text.startsWith('https://'))
        OutlinedButton.icon(
          onPressed: () => run(c, () => c.resolve(search.text)),
          icon: const Icon(Icons.link_rounded),
          label: Text(wt('native.0556f90ffc', context: context)),
        ),
    ],
  );
  Future<Json?> roomCreation() async {
    final name = TextEditingController();
    bool public = false;
    try {
      return await showWaveDialog<Json>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: Text(wt('native.2e0b4996ef', context: dialog)),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: wt('native.55c12495ec', context: dialog),
                    ),
                    onChanged: (_) => update(() {}),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: public,
                    title: Text(wt('room.public', context: dialog)),
                    subtitle: Text(
                      wt(
                        public ? 'room.publicHint' : 'room.privateHint',
                        context: dialog,
                      ),
                    ),
                    onChanged: (value) => update(() => public = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(wt('native.0ec753be8d', context: dialog)),
              ),
              FilledButton(
                onPressed: name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialog, {
                        'name': name.text.trim(),
                        'public': public,
                      }),
                child: Text(wt('native.3643850b0a', context: dialog)),
              ),
            ],
          ),
        ),
      );
    } finally {
      // showWaveDialog waits for the route widgets to unmount.
      name.dispose();
    }
  }

  Future<void> showPlayer({WaveTrack? track, int tab = 0}) async {
    playerInitialTab = tab;
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
              leading: Icon(
                c.playlistsForTrack(track.id).isEmpty
                    ? Icons.playlist_add_rounded
                    : Icons.playlist_add_check_rounded,
                color: c.playlistsForTrack(track.id).isEmpty
                    ? null
                    : waveVisuals(context).accent,
              ),
              title: Text(membershipLabel(context, c, track)),
              onTap: () {
                Navigator.pop(sheet);
                showPlaylistMembership(context, c, track);
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
            if (c.online && c.loggedIn)
              for (final artist in [false, true])
                ListTile(
                  leading: Icon(
                    artist ? Icons.person_off_outlined : Icons.block_rounded,
                  ),
                  title: Text(
                    wave27Text(context, artist ? 'hideArtist' : 'hideTrack'),
                  ),
                  onTap: () {
                    Navigator.pop(sheet);
                    unawaited(
                      excludeRecommendation(context, c, track, artist: artist),
                    );
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
      for (final entry in ['soundcloud', 'spotify', 'yandex', 'youtube'].map(
        (provider) =>
            c.integrations
                .where((item) => item['provider'] == provider)
                .firstOrNull ??
            <String, dynamic>{'provider': provider},
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                                    values: {
                                      'p0': (entry['displayName'] ?? ''),
                                    },
                                    context: context,
                                  )
                                : publicImportText(context, 'hint'),
                            style: TextStyle(
                              fontSize: 11,
                              color: waveVisuals(context).muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: Key('public-import-open-${entry['provider']}'),
                  onPressed: () => sourcePlaylists(entry['provider'] as String),
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: Text(publicImportText(context, 'open')),
                ),
                if (entry['connected'] == true)
                  Column(
                    children: [
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
                          : publicImportText(context, 'connected'),
                    ),
                  ),
              ],
            ),
          ),
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
    if (c.user == null) return;
    if (c.user?.plan == 'free') {
      c.tell(publicImportText(context, 'plan'));
      return;
    }
    await showProviderImport(
      context,
      c,
      provider,
      connected: c.integrations.any(
        (item) => item['provider'] == provider && item['connected'] == true,
      ),
    );
  }

  Widget downloads() => NativeSavedView(
    controller: c,
    onMore: more,
    onBrowse: () => navigate(WavePage.search),
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
                final creation = await roomCreation();
                if (creation != null) {
                  await run(
                    c,
                    () => c.createRoom(
                      creation['name'] as String,
                      public: creation['public'] == true,
                    ),
                  );
                }
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
        if (c.rooms.isEmpty && c.publicRooms.isEmpty)
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
        section(wt('native.1d2a1d354c', context: context)),
        Surface(
          child: Column(
            children: [
              for (final member in objects(c.room!['members']))
                Row(
                  children: [
                    ClipOval(
                      child: Artwork(
                        controller: c,
                        url: member['avatarUrl']?.toString(),
                        size: 36,
                        radius: 0,
                        icon: Icons.person_outline_rounded,
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
                          const SizedBox(height: 6),
                          Text(
                            memberListening(member)
                                ? ecosystemText('listening', context)
                                : wt(
                                    member['online'] == true
                                        ? 'room.online'
                                        : 'native.67b99cc9bf',
                                    context: context,
                                  ),
                            style: TextStyle(
                              color: waveVisuals(context).muted,
                              fontSize: 11,
                            ),
                          ),
                          for (final device in objects(member['devices']))
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Row(
                                children: [
                                  DevicePlatformIcon(
                                    device: device,
                                    size: 14,
                                    color: device['outputActive'] == true
                                        ? waveVisuals(context).accent
                                        : waveVisuals(context).muted,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${deviceKindLabel(device, context: context)}${device['name'] != null ? ' · ${device['name']}' : ''}${device['outputActive'] == true ? ' · ${wt(device['playing'] == true ? 'devices.activeOutput' : 'devices.selectedOutput', context: context)}' : ''}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: waveVisuals(context).muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (c.room!['type'] != 'jam' &&
                        c.canManageRoom &&
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
      RoomDirectory(controller: c),
    ],
  );
  Future<void> sendMessage() async {
    final value = chat.text;
    await run(c, () async {
      await c.roomMessage(value);
      chat.clear();
    });
  }

  Widget devicesPage() =>
      ConnectPanel(controller: c, scanQr: scanQr, discover: discover);

  Widget roomPin() {
    final v = waveVisuals(context);
    return Material(
      color: v.accentSoft,
      child: InkWell(
        key: const Key('pinned-room'),
        onTap: () => navigate(WavePage.rooms),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          child: Row(
            children: [
              ListeningPresence(
                controller: c,
                compact: true,
                onTap: () => navigate(WavePage.rooms),
              ),
              const SizedBox(width: 6),
              Icon(Icons.headphones_rounded, color: v.accent, size: 19),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.room?['name']?.toString() ??
                          wt('room.pinned', context: context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${wt(c.connected ? 'room.online' : 'room.reconnecting', context: context)} · ${c.outputLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: v.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: wt('native.5aeda8f0be', context: context),
                onPressed: () => run(c, c.leaveRoom),
                icon: const Icon(Icons.logout_rounded, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      final uri = Uri.tryParse(value!);
      if (uri?.scheme == 'glukwave' && uri?.host == 'lan') {
        await c.connectLan(value);
        return;
      }
      final info = await c.qrInfo(value);
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
      CollectionDestination(
        key: const Key('profile-guard'),
        title: nativeText(context, 'guard'),
        subtitle: nativeText(context, 'guardDetail'),
        icon: Icons.qr_code_scanner_rounded,
        onTap: () => showWaveGuard(context, c),
      ),
      const SizedBox(height: 22),
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
                            Wrap(
                              spacing: 10,
                              runSpacing: 3,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  c.user!.displayName,
                                  style: const TextStyle(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.6,
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    c.user!.admin
                                        ? 'ADMIN'
                                        : c.user!.plan == 'beta'
                                        ? 'β BETA'
                                        : c.user!.plan == 'unbound'
                                        ? 'UNBOUND'
                                        : 'FREE',
                                  ),
                                  backgroundColor: waveVisuals(
                                    context,
                                  ).accentSoft,
                                  side: BorderSide.none,
                                  labelStyle: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: editProfile,
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: Text(wt('native.dd5a0b517a', context: context)),
                      ),
                      if (c.user!.avatar.isNotEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              run(c, () => c.removeProfileMedia('avatar')),
                          icon: const Icon(
                            Icons.person_remove_outlined,
                            size: 16,
                          ),
                          label: Text(
                            wt('profile.removeAvatar', context: context),
                          ),
                        ),
                      if (c.user!.banner.isNotEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              run(c, () => c.removeProfileMedia('banner')),
                          icon: const Icon(
                            Icons.image_not_supported_outlined,
                            size: 16,
                          ),
                          label: Text(
                            wt('profile.removeBanner', context: context),
                          ),
                        ),
                    ],
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
            icon: const WaveControlIcon(Icons.settings_rounded),
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
            if (c.user!.plan != 'beta')
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
      const SizedBox(height: 24),
      ListeningStats(controller: c),
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
        'taste': (pt(context, 'Taste'), Icons.waves_rounded),
        'privacy': (pt(context, 'Privacy'), Icons.shield_outlined),
        'appearance': (
          wt('native.d206f1bed0', context: context),
          Icons.palette_outlined,
        ),
        'security': (
          wt('sessions.security', context: context),
          Icons.security_rounded,
        ),
        'playback': (
          wt('native.5dcbecbd1a', context: context),
          Icons.graphic_eq_rounded,
        ),
        if (Platform.isAndroid)
          'homeWidgets': (
            homeWidgetText('title', context: context),
            Icons.widgets_outlined,
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
          onTap: () => setState(() {
            settingsSection = item.key;
            settingsQuery = '';
            settingsSearch.clear();
          }),
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
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: desktop ? 128 : double.infinity,
                  ),
                  child: Text(
                    item.value.$1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: settingsSection == item.key
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: settingsSection == item.key ? v.ink : v.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final matches = settingsSections.entries
        .where(
          (item) =>
              '${item.key} ${item.value.$1} ${switch (item.key) {
                    'playback' => 'audio sound volume equalizer EQ lyrics звук громкость эквалайзер текст',
                    'storage' => 'cache offline memory downloads кеш память загрузки',
                    'appearance' => 'theme color animation background язык language тема цвет анимация',
                    'security' => 'sessions password privacy сессии пароль безопасность',
                    _ => '',
                  }}'
                  .toLowerCase()
                  .contains(settingsQuery.trim().toLowerCase()),
        )
        .toList();
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
        TextField(
          controller: settingsSearch,
          key: const Key('settings-search'),
          decoration: InputDecoration(
            labelText: wave26Text(context, 'settings.search'),
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            suffixIcon: settingsQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(() {
                      settingsSearch.clear();
                      settingsQuery = '';
                    }),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
          onChanged: (value) => setState(() => settingsQuery = value),
        ),
        const SizedBox(height: 18),
        if (!desktop) ...[
          if (settingsQuery.isEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey('settings-mobile-$settingsSection'),
              isExpanded: true,
              initialValue: settingsSection,
              decoration: InputDecoration(
                labelText: wave26Text(context, 'settings.category'),
              ),
              items: [
                for (final item in settingsSections.entries)
                  DropdownMenuItem(
                    value: item.key,
                    child: Text(
                      item.value.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => settingsSection = value);
              },
            )
          else if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(wave26Text(context, 'settings.noResults')),
            )
          else
            SingleChildScrollView(
              key: const Key('settings-navigation'),
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final item in matches) link(item)]),
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
                        key: const Key('desktop-settings-navigation'),
                        children: [
                          if (matches.isEmpty)
                            Text(wave26Text(context, 'settings.noResults')),
                          for (final item in matches) link(item),
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
      'homeWidgets' => Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              homeWidgetText('title', context: context),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              homeWidgetText('detail', context: context),
              style: TextStyle(color: v.muted),
            ),
            const SizedBox(height: 22),
            HomeWidgetPreviews(
              track: c.audio.viewCurrent,
              playing: c.audio.playing,
              loading: c.trackLoading,
              signedIn: c.loggedIn,
              liked: c.likedIds.contains(c.audio.viewCurrent?.id),
              artwork: Artwork(
                controller: c,
                url: c.audio.viewCurrent?.artwork,
                size: 44,
              ),
              labels: HomeWidgetPreviewLabels(
                text: (key) => homeWidgetText(key, context: context),
              ),
              onPinPlayer: () => run(c, () async {
                if (await c.homeWidgets?.pin('player') != true) {
                  c.tell(homeWidgetText('manual'));
                }
              }),
              onPinWave: () => run(c, () async {
                if (await c.homeWidgets?.pin('wave') != true) {
                  c.tell(homeWidgetText('manual'));
                }
              }),
            ),
          ],
        ),
      ),
      'taste' => Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeading(pt(context, 'Taste'), pt(context, 'Taste subtitle')),
            FilledButton.icon(
              onPressed: () => openTaste(context, c, parity),
              icon: const Icon(Icons.waves_rounded),
              label: Text(pt(context, 'Start')),
            ),
          ],
        ),
      ),
      'privacy' => PrivacyPanel(controller: c),
      'appearance' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.appearanceStore != null)
            AppearanceEntry(
              store: c.appearanceStore!,
              advancedAllowed: c.user?.plan != 'free',
            ),
          const SizedBox(height: 18),
          TypographyPanel(controller: c),
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
          NativeEnergyPanel(controller: c),
          const SizedBox(height: 18),
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
                settingSwitch(pt(context, 'Comments'), '', 'comments'),
                const Divider(height: 32),
                settingSwitch(
                  pt(context, 'Lyrics under cover'),
                  '',
                  'lyricsUnderCover',
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
                  wave26Text(context, 'settings.cacheNote'),
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
          DiscordPanel(controller: c),
          const SizedBox(height: 24),
          sourcesPage(),
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
      'security' => Column(
        children: [
          SessionsPanel(controller: c),
          const SizedBox(height: 18),
          AccountActions(controller: c),
        ],
      ),
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
            WaveUpdateNotice(controller: c, settings: true),
            const SizedBox(height: 18),
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
        AdminParity(controller: widget.controller),
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
