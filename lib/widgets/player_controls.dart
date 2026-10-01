import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.isPlaying,
    required this.lofiMode,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onToggleLofi,
  });

  final bool isPlaying;
  final bool lofiMode;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onToggleLofi;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(onPressed: onPrevious, icon: const Icon(Icons.skip_previous_rounded)),
            FilledButton.tonalIcon(
              onPressed: onPlayPause,
              icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(isPlaying ? 'Пауза' : 'Старт'),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.skip_next_rounded)),
          ],
        ),
        const SizedBox(height: 4),
        FilterChip(
          selected: lofiMode,
          onSelected: (_) => onToggleLofi(),
          avatar: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Lo-fi режим'),
        ),
      ],
    );
  }
}
