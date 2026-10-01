import 'package:flutter/material.dart';

enum WaveMood { calm, focus, energy }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.genre,
    required this.mood,
    required this.coverColor,
    required this.soundCloudUrl,
  });

  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String genre;
  final WaveMood mood;
  final Color coverColor;
  final String soundCloudUrl;

  String get durationLabel {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
