import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../core/controller.dart';
import '../services/provider_player.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';

/// Kept above the navigator: changing library/search/room pages cannot destroy
/// the source player or reset its position. The official player remains visible.
class PersistentProviderHost extends StatefulWidget {
  final WaveController controller;
  final Widget child;
  const PersistentProviderHost({
    super.key,
    required this.controller,
    required this.child,
  });
  @override
  State<PersistentProviderHost> createState() => _PersistentProviderHostState();
}

class _PersistentProviderHostState extends State<PersistentProviderHost>
    with WidgetsBindingObserver {
  ProviderPlayer get player => widget.controller.audio.provider;
  WebViewEnvironment? environment;
  bool prepared = !Platform.isWindows;
  String? unavailable;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      if (await WebViewEnvironment.getAvailableVersion() == null) {
        throw const FormatException('WebView2 unavailable');
      }
      environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: path.join(
            (await getApplicationSupportDirectory()).path,
            'provider-webview',
          ),
        ),
      );
      if (mounted) setState(() => prepared = true);
    } catch (_) {
      if (mounted) setState(() => unavailable = 'provider.runtime');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = ![
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ].contains(state);
    unawaited(
      player.evaluate
          ?.call('window.waveVisibility?.(${foreground ? 'true' : 'false'});')
          .catchError((Object _) {}),
    );
    if (Platform.isAndroid &&
        player.track?.source == 'youtube' &&
        [
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.detached,
        ].contains(state)) {
      // YouTube's official video player stays a foreground experience.
      unawaited(widget.controller.audio.localCommand('pause'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player.evaluate = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: player,
    builder: (context, _) {
      final track = player.track;
      final visible = track != null && !widget.controller.audio.remote;
      final v = waveVisuals(context);
      return Column(
        children: [
          Expanded(child: widget.child),
          if (track != null)
            Offstage(
              offstage: !visible,
              child: Material(
                color: v.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              track.source == 'youtube'
                                  ? Icons.smart_display_outlined
                                  : Icons.cloud_outlined,
                              size: 15,
                              color: v.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                wt(
                                  'provider.inside',
                                  values: {'source': track.sourceName},
                                  context: context,
                                ),
                                style: TextStyle(fontSize: 10, color: v.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (player.loading)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: track.source == 'youtube' ? 200 : 100,
                          width: double.infinity,
                          child: unavailable != null
                              ? Center(
                                  child: Text(
                                    wt(unavailable!, context: context),
                                  ),
                                )
                              : !prepared
                              ? const Center(child: CircularProgressIndicator())
                              : InAppWebView(
                                  key: ValueKey(
                                    'provider-${player.generation}',
                                  ),
                                  webViewEnvironment: environment,
                                  initialData: InAppWebViewInitialData(
                                    data: providerDocument(
                                      track,
                                      player.generation,
                                      Uri.parse(
                                        widget.controller.appUrl,
                                      ).origin,
                                    ),
                                    baseUrl: WebUri(
                                      '${Uri.parse(widget.controller.appUrl).origin}/native-player/',
                                    ),
                                  ),
                                  initialSettings: InAppWebViewSettings(
                                    javaScriptEnabled: true,
                                    mediaPlaybackRequiresUserGesture: false,
                                    allowsInlineMediaPlayback: true,
                                    transparentBackground: true,
                                    supportMultipleWindows: false,
                                    useShouldOverrideUrlLoading: true,
                                  ),
                                  onWebViewCreated: (view) {
                                    final generation = player.generation;
                                    player.evaluate = (script) async {
                                      await view.evaluateJavascript(
                                        source: script,
                                      );
                                    };
                                    view.addJavaScriptHandler(
                                      handlerName: 'waveProvider',
                                      callback: (arguments) {
                                        if (arguments.length == 2 &&
                                            arguments[0] == generation) {
                                          player.receive(
                                            generation,
                                            arguments[1],
                                          );
                                        }
                                        return null;
                                      },
                                    );
                                  },
                                  shouldOverrideUrlLoading:
                                      (view, action) async {
                                        if (action.isForMainFrame &&
                                            action.request.url?.path !=
                                                '/native-player/' &&
                                            action.request.url?.scheme !=
                                                'about') {
                                          return NavigationActionPolicy.CANCEL;
                                        }
                                        return NavigationActionPolicy.ALLOW;
                                      },
                                  onReceivedError: (view, request, error) {
                                    if (request.isForMainFrame == true) {
                                      player.receive(player.generation, {
                                        'event': 'error',
                                      });
                                    }
                                  },
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
  );
}
