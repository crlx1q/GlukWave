import 'package:flutter/material.dart';

import 'models.dart';

class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.track, this.size = 210});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [track.coverColor.withOpacity(0.95), const Color(0xFF111322)],
        ),
        boxShadow: [
          BoxShadow(
            color: track.coverColor.withOpacity(0.35),
            blurRadius: 30,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.graphic_eq_rounded, size: 80, color: Colors.white),
      ),
    );
  }
}
