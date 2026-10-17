import 'package:flutter/material.dart';
import '../l10n/wave_localizations.dart';
import 'theme.dart';

/// App notices live above routes, below the safe top, and never displace content.
class WaveTopNotice extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const WaveTopNotice({super.key, required this.text, required this.onClose});
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Semantics(liveRegion: true, child: Material(
              key: const Key('wave-top-notice'),
              color: v.surface,
              elevation: 12,
              shadowColor: Colors.black.withValues(alpha: .2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: v.line)),
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: v.accent),
                  const SizedBox(width: 10),
                  Flexible(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(text, style: TextStyle(color: v.ink, fontSize: 12, height: 1.5)))),
                  IconButton(onPressed: onClose, icon: Icon(Icons.close_rounded, size: 17, semanticLabel: wt('native.4ae50d3073', context: context)), constraints: const BoxConstraints(minWidth: 44, minHeight: 44)),
                ]),
              ),
            )),
          ),
        ),
      ),
    );
  }
}
