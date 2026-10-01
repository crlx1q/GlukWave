import 'package:flutter/material.dart';

import '../main.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);

    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Библиотека', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Коллекция треков для персональной волны и Lo-fi атмосферы.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...appState.tracks.map(
              (track) => Card(
                child: ListTile(
                  title: Text(track.title),
                  subtitle: Text('${track.artist} • ${track.genre}'),
                  trailing: Text(track.durationLabel),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (appState.currentSoundCloudUri != null)
              Text(
                'SoundCloud: ${appState.currentSoundCloudUri}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );
      },
    );
  }
}
