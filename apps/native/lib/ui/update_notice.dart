import 'package:flutter/material.dart';
import '../services/app_updates.dart';
import '../core/controller.dart';
import '../l10n/glukwave27_ui_strings.dart';
import 'widgets.dart';

class WaveUpdateNotice extends StatelessWidget {
  final WaveController controller;
  final bool settings;
  const WaveUpdateNotice({
    super.key,
    required this.controller,
    this.settings = false,
  });
  @override
  Widget build(BuildContext context) {
    final updater = controller.updater;
    if (updater == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: updater,
      builder: (_, child) {
        final u = updater, v = waveVisuals(context), release = u.release;
        if (!u.visible && !settings) return const SizedBox.shrink();
        final downloading = u.phase == UpdatePhase.downloading,
            installing = u.phase == UpdatePhase.installing,
            checking = u.phase == UpdatePhase.checking,
            ready = u.phase == UpdatePhase.ready;
        Widget button(
          String label,
          VoidCallback? action, {
          bool primary = false,
        }) => primary
            ? FilledButton(onPressed: action, child: Text(label))
            : TextButton(onPressed: action, child: Text(label));
        return Container(
          key: const Key('wave-update-notice'),
          margin: settings
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(18, 8, 18, 6),
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
          decoration: BoxDecoration(
            color: v.surface,
            border: Border.all(color: v.line),
            borderRadius: BorderRadius.circular(v.corners(14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.system_update_alt_rounded,
                    color: v.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          wave27Text(
                            context,
                            release != null ? 'update' : 'current',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          release?.version ?? u.currentVersion,
                          style: TextStyle(color: v.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (!settings)
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: downloading || installing ? null : u.dismiss,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
              ),
              if (downloading) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: u.progress,
                    color: v.accent,
                    backgroundColor: v.line,
                    minHeight: 3,
                  ),
                ),
              ],
              if (installing ||
                  checking ||
                  downloading ||
                  u.phase == UpdatePhase.error)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    wave27Text(
                          context,
                          installing
                              ? 'installing'
                              : checking
                              ? 'checking'
                              : downloading
                              ? 'downloading'
                              : 'error',
                        ) +
                        (downloading
                            ? ' ·  ${(u.progress * 100).round()}%'
                            : ''),
                    style: TextStyle(color: v.muted, fontSize: 11, height: 1.5),
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (settings)
                    button(
                      wave27Text(context, 'check'),
                      checking || downloading || installing
                          ? null
                          : () => u.check(force: true),
                    ),
                  if (downloading)
                    button(wave27Text(context, 'cancelDownload'), u.cancel),
                  if (release != null &&
                      !downloading &&
                      !installing &&
                      !checking)
                    button(
                      wave27Text(
                        context,
                        ready
                            ? 'install'
                            : u.phase == UpdatePhase.error
                            ? 'retry'
                            : 'download',
                      ),
                      ready ? () => u.install() : () => u.download(),
                      primary: true,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
