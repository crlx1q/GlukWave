import 'package:flutter/material.dart';

import '../models.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final Track track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: track.coverColor),
        title: Text(track.title, style: textTheme.titleMedium),
        subtitle: Text('${track.artist} • ${track.genre}'),
        trailing: selected
            ? const Icon(Icons.equalizer_rounded)
            : Text(track.durationLabel, style: textTheme.bodySmall),
      ),
    );
  }
}
