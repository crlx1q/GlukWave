import 'package:flutter/material.dart';

import '../app_state.dart';
import '../cover_art.dart';
import '../main.dart';
import '../widgets/player_controls.dart';
import '../widgets/track_tile.dart';
import '../wave_hero.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);

    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final track = appState.currentTrack;

        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Gluk Wave', style: Theme.of(context).textTheme.headlineSmall),
                        Text(track.durationLabel, style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CoverArt(track: track),
                    const SizedBox(height: 16),
                    Text(track.title, style: Theme.of(context).textTheme.titleLarge),
                    Text('${track.artist} • ${track.genre}'),
                  ],
                ),
              ),
              SizedBox(height: 120, child: WaveHero(signal: appState.synth.wave)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PlayerControls(
                  isPlaying: appState.isPlaying,
                  lofiMode: appState.lofiMode,
                  onPrevious: appState.previousTrack,
                  onPlayPause: appState.togglePlay,
                  onNext: appState.nextTrack,
                  onToggleLofi: appState.toggleLofiMode,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: appState.tracks.length,
                  itemBuilder: (context, index) {
                    final item = appState.tracks[index];
                    return TrackTile(
                      track: item,
                      selected: index == appState.currentIndex,
                      onTap: () => appState.selectTrack(index),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
