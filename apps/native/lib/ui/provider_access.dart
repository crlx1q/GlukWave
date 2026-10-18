import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/glukwave27_ui_strings.dart';
import 'widgets.dart';

class ProviderAccess extends StatefulWidget {
  final WaveController controller;
  final String provider;
  final VoidCallback onConnected;
  const ProviderAccess({
    super.key,
    required this.controller,
    required this.provider,
    required this.onConnected,
  });
  @override
  State<ProviderAccess> createState() => _ProviderAccessState();
}

class _ProviderAccessState extends State<ProviderAccess> {
  WaveController get c => widget.controller;
  final token = TextEditingController();
  bool open = false, busy = false;
  String? error, account, origin;
  Json connection = {};
  int generation = 0;
  @override
  void initState() {
    super.initState();
    account = c.user?.id;
    origin = c.api.server;
    c.addListener(scopeChanged);
    unawaited(refresh());
  }

  void scopeChanged() {
    if (account == c.user?.id && origin == c.api.server) return;
    generation++;
    token.clear();
    if (mounted) {
      setState(() {
        open = busy = false;
        error = null;
        connection = {};
        account = c.user?.id;
        origin = c.api.server;
      });
    }
  }

  Future<void> refresh() async {
    final request = ++generation;
    try {
      final data = await c.api.call('/api/integrations');
      if (mounted && request == generation) {
        setState(
          () => connection =
              objects(data['connections'])
                  .where((item) => item['provider'] == widget.provider)
                  .firstOrNull ??
              {},
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    generation++;
    c.removeListener(scopeChanged);
    token.clear();
    token.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || token.text.trim().isEmpty) return;
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await c.api.call(
        widget.provider == 'spotify'
            ? '/api/public-import/spotify/token'
            : '/api/integrations/yandex/token',
        method: 'POST',
        data: {'accessToken': token.text.trim()},
      );
      if (mounted && request == generation) {
        token.clear();
        setState(() {
          open = false;
          connection = object(data['connection']);
        });
        widget.onConnected();
      }
    } catch (reason) {
      if (mounted && request == generation) {
        setState(() => error = reason.toString());
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  void cancel() {
    generation++;
    token.clear();
    setState(() {
      open = false;
      busy = false;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!['spotify', 'yandex'].contains(widget.provider)) {
      return const SizedBox.shrink();
    }
    final v = waveVisuals(context);
    String text(String key) => wave27Text(context, key);
    return Container(
      key: const Key('provider-private-access'),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: v.background,
        border: Border.all(color: v.line),
        borderRadius: BorderRadius.circular(v.corners(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 18, color: v.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text('access'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (connection['connected'] == true)
                Icon(Icons.check_rounded, size: 17, color: v.accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text(
              widget.provider == 'yandex' &&
                      connection['serverTokenAvailable'] == true
                  ? 'serverToken'
                  : 'publicCatalog',
            ),
            style: TextStyle(fontSize: 11, height: 1.6, color: v.muted),
          ),
          if (connection['displayName'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                connection['displayName'].toString(),
                style: TextStyle(fontSize: 11, color: v.accent),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (widget.provider == 'spotify')
                OutlinedButton(
                  onPressed: connection['configured'] == true && !busy
                      ? () =>
                            c.connectProvider('spotify').catchError((Object e) {
                              if (mounted) setState(() => error = e.toString());
                            })
                      : null,
                  child: Text(text('oauth')),
                ),
              TextButton(
                key: const Key('provider-manual-token'),
                onPressed: busy
                    ? null
                    : () => open ? cancel() : setState(() => open = true),
                child: Text(text('manual')),
              ),
            ],
          ),
          if (open) ...[
            const Divider(height: 24),
            TextField(
              key: const Key('provider-access-token'),
              controller: token,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 8192,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => save(),
              decoration: InputDecoration(
                labelText: text('token'),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              text('tokenHint'),
              style: TextStyle(color: v.muted, fontSize: 11, height: 1.6),
            ),
            if (widget.provider == 'spotify')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  text('spotifyScopes'),
                  style: TextStyle(color: v.muted, fontSize: 11, height: 1.6),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => c.openUrl(
                    'https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabb9972e14713915d23b71bb85591',
                  ),
                  child: Text(text('oauthYandex')),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const Key('provider-save-token'),
                  onPressed: busy ? null : save,
                  child: Text(busy ? '…' : text('saveToken')),
                ),
                TextButton(onPressed: cancel, child: Text(text('close'))),
              ],
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                error!,
                style: TextStyle(color: v.ink, fontSize: 11, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}
