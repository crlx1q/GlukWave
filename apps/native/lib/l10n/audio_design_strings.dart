import 'package:flutter/widgets.dart';
import 'wave_localizations.dart';

String audioDesignText(String key, {BuildContext? context}) {
  final lang = context == null
          ? WaveStrings.current.language
          : WaveStrings.of(context).language,
      i = ['en', 'ru', 'kk', 'uk', 'de', 'es'].indexOf(lang);
  return audioDesignStrings[key]?[i < 0 ? 0 : i] ?? key;
}

const audioDesignStrings = <String, List<String>>{
  'loadingPlayback': [
    'Loading audio',
    'Загружаем трек',
    'Трек жүктелуде',
    'Завантажуємо трек',
    'Audio wird geladen',
    'Cargando audio',
  ],
  'coverAccent': [
    'Colour from the cover',
    'Цвет из обложки',
    'Мұқаба түсі',
    'Колір з обкладинки',
    'Farbe vom Cover',
    'Color de la portada',
  ],
  'coverAccentCaption': [
    'Your controls and wave follow the album. Turn off to keep your palette.',
    'Кнопки и волна следуют цвету альбома. Выключи, чтобы сохранить свою палитру.',
    'Түймелер мен толқын альбом түсіне бейімделеді. Өз палитраң үшін өшір.',
    'Кнопки й хвиля слідують кольору альбому. Вимкни, щоб зберегти свою палітру.',
    'Bedienelemente und Welle folgen dem Album. Ausschalten, um deine Palette zu behalten.',
    'Los controles y la onda siguen el álbum. Desactiva para mantener tu paleta.',
  ],
  'savePreset': [
    'Save my curve',
    'Сохранить мою кривую',
    'Қисықты сақтау',
    'Зберегти мою криву',
    'Meine Kurve speichern',
    'Guardar mi curva',
  ],
  'savedPreset': [
    'My curve',
    'Моя кривая',
    'Менің қисығым',
    'Моя крива',
    'Meine Kurve',
    'Mi curva',
  ],
  'reset': [
    'Reset',
    'Сбросить',
    'Қалпына келтіру',
    'Скинути',
    'Zurücksetzen',
    'Restablecer',
  ],
};
