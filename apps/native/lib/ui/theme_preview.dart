import 'package:flutter/material.dart';
import '../core/appearance.dart';
import 'theme.dart';

class ThemePreview extends StatelessWidget {
  final String label;
  final WavePalette palette;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const ThemePreview({
    super.key,
    required this.label,
    required this.palette,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final accent = hexColor(palette.accent),
        ink = hexColor(palette.ink),
        surface = hexColor(palette.surface),
        bg = hexColor(palette.bg),
        radius = waveVisuals(context).corners(14);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: 124,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected
                  ? waveVisuals(context).accent
                  : waveVisuals(context).line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 70,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          color: surface,
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            children: [
                              for (var i = 0; i < 3; i++)
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(bottom: 5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: accent.withValues(alpha: .6),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 65,
                                  height: 4,
                                  color: ink.withValues(alpha: .25),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  width: 40,
                                  height: 4,
                                  color: ink.withValues(alpha: .15),
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: .2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (selected)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: waveVisuals(context).accent,
                          size: 15,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                child: Row(
                  children: [
                    Icon(icon, color: ink, size: 13),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
