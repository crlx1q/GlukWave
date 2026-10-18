import '../l10n/glukwave27_ui_strings.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../core/controller.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';

/// The main Windows frame belongs to the listening room. Compact tray windows
/// retain their own drag surfaces and do not mount a second set of controls.
class DesktopTitleBar extends StatefulWidget {
  final WaveController controller;
  const DesktopTitleBar({super.key, required this.controller});
  static bool get supported => Platform.isWindows;
  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool maximized = false;
  WaveController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (c.desktop.initialized) unawaited(readWindow());
  }

  Future<void> readWindow() async {
    final value = await windowManager.isMaximized();
    if (mounted) setState(() => maximized = value);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => maximized = false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> toggle() async {
    if (!c.desktop.initialized) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) => Material(
        color: v.background,
        child: SizedBox(
          key: const Key('desktop-titlebar'),
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: toggle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Brand(size: 21, animated: false),
                            const SizedBox(width: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: v.surface,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: v.line),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: c.online
                                          ? const Color(0xff78a28a)
                                          : v.muted,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    wt(
                                      c.online
                                          ? 'native.011e2099f2'
                                          : 'native.67b99cc9bf',
                                      context: context,
                                    ),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: v.muted,
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: v.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: v.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _button(
                        'desktop-window-minimize',
                        wave27Text(context, 'minimize'),
                        Icons.remove_rounded,
                        () => windowManager.minimize(),
                      ),
                      _button(
                        'desktop-window-maximize',
                        wave27Text(context, 'maximize'),
                        maximized
                            ? Icons.filter_none_rounded
                            : Icons.crop_square_rounded,
                        toggle,
                      ),
                      _button(
                        'desktop-window-close',
                        MaterialLocalizations.of(context).closeButtonLabel,
                        Icons.close_rounded,
                        () => windowManager.close(),
                        close: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(
    String key,
    String label,
    IconData icon,
    Future<void> Function() action, {
    bool close = false,
  }) => IconButton(
    key: Key(key),
    tooltip: label,
    onPressed: c.desktop.initialized ? () => unawaited(action()) : null,
    style: IconButton.styleFrom(
      minimumSize: const Size(40, 32),
      maximumSize: const Size(40, 32),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      hoverColor: close
          ? Colors.redAccent.withValues(alpha: .18)
          : waveVisuals(context).accentSoft,
      foregroundColor: close ? Colors.redAccent : waveVisuals(context).muted,
    ),
    icon: Icon(icon, size: 15),
  );
}
