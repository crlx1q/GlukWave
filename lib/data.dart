import 'package:flutter/material.dart';

import 'models.dart';

const demoTracks = <Track>[
  Track(
    id: 'nochnaya-volna',
    title: 'Ночная волна',
    artist: 'Gluk Wave',
    duration: Duration(minutes: 3, seconds: 47),
    genre: 'Lo-fi',
    mood: WaveMood.calm,
    coverColor: Color(0xFF5B4DFF),
    soundCloudUrl: 'https://soundcloud.com/',
  ),
  Track(
    id: 'tuman-v-gorode',
    title: 'Туман в городе',
    artist: 'Neon District',
    duration: Duration(minutes: 4, seconds: 12),
    genre: 'Downtempo',
    mood: WaveMood.focus,
    coverColor: Color(0xFF2AA8F2),
    soundCloudUrl: 'https://soundcloud.com/',
  ),
  Track(
    id: 'teplyj-shum',
    title: 'Тёплый шум',
    artist: 'Kaseta 84',
    duration: Duration(minutes: 2, seconds: 59),
    genre: 'Synthwave',
    mood: WaveMood.energy,
    coverColor: Color(0xFFFF5A8A),
    soundCloudUrl: 'https://soundcloud.com/',
  ),
  Track(
    id: 'vetra-krysh',
    title: 'Ветра крыш',
    artist: 'Stereo Lines',
    duration: Duration(minutes: 5, seconds: 8),
    genre: 'Ambient',
    mood: WaveMood.calm,
    coverColor: Color(0xFF53C779),
    soundCloudUrl: 'https://soundcloud.com/',
  ),
];
