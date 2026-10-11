import 'package:flutter/widgets.dart';
import 'wave_localizations.dart';

String focusedPlayerText(String key, {BuildContext? context}) {
  final lang = context == null
      ? WaveStrings.current.language
      : WaveStrings.of(context).language;
  final i = ['en', 'ru', 'kk', 'uk', 'de', 'es'].indexOf(lang);
  return focusedPlayerStrings[key]?[i < 0 ? 0 : i] ?? key;
}

const focusedPlayerStrings = <String, List<String>>{
  'nowPlaying': [
    'Now playing',
    'Сейчас играет',
    'Қазір ойнап тұр',
    'Зараз грає',
    'Läuft gerade',
    'Reproduciendo',
  ],
  'more': [
    'More controls',
    'Другие действия',
    'Қосымша әрекеттер',
    'Інші дії',
    'Weitere Aktionen',
    'Más controles',
  ],
  'coverStyle': [
    'Cover appearance',
    'Вид обложки',
    'Мұқаба көрінісі',
    'Вигляд обкладинки',
    'Cover-Ansicht',
    'Apariencia de portada',
  ],
};
