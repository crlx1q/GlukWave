import 'package:flutter/widgets.dart';
import 'wave_localizations.dart';

String seasonText(String key, {BuildContext? context}) {
  final language = context == null
      ? WaveStrings.current.language
      : WaveStrings.of(context).language;
  final index = ['en', 'ru', 'kk', 'uk', 'de', 'es'].indexOf(language);
  return _strings[key.startsWith('season.') ? key : 'season.$key']?[index < 0
          ? 0
          : index] ??
      key;
}

const _strings = <String, List<String>>{
  "season.title": [
    "Seasonal atmosphere",
    "Сезонная атмосфера",
    "Маусымдық атмосфера",
    "Сезонна атмосфера",
    "Saisonale Atmosphäre",
    "Ambiente de temporada",
  ],
  "season.caption": [
    "A little weather in your musical space. Off by default.",
    "Немного погоды в твоём музыкальном мире. По умолчанию выключено.",
    "Музыкалық кеңістігіңдегі ауа райы. Әдепкіде өшірулі.",
    "Трохи погоди у твоєму музичному світі. Типово вимкнено.",
    "Ein wenig Wetter in deinem Musikraum. Standardmäßig aus.",
    "Un poco de clima en tu espacio musical. Desactivado por defecto.",
  ],
  "season.auto": [
    "Follow the season",
    "По времени года",
    "Маусымға сай",
    "За порою року",
    "Nach Jahreszeit",
    "Según la estación",
  ],
  "season.snow": [
    "Snowfall",
    "Снежинки",
    "Қар",
    "Сніжинки",
    "Schneeflocken",
    "Copos de nieve",
  ],
  "season.rain": [
    "Raindrops",
    "Капли дождя",
    "Жаңбыр тамшылары",
    "Краплі дощу",
    "Regentropfen",
    "Gotas de lluvia",
  ],
  "season.leaves": [
    "Falling leaves",
    "Листопад",
    "Жапырақтар",
    "Листопад",
    "Fallende Blätter",
    "Hojas cayendo",
  ],
  "season.sun": [
    "Sunlight",
    "Солнечные лучи",
    "Күн сәулесі",
    "Сонячні промені",
    "Sonnenstrahlen",
    "Rayos de sol",
  ],
  "season.mode": [
    "Atmosphere",
    "Атмосфера",
    "Атмосфера",
    "Атмосфера",
    "Atmosphäre",
    "Ambiente",
  ],
  "season.intensity": [
    "Intensity",
    "Интенсивность",
    "Қарқындылық",
    "Інтенсивність",
    "Intensität",
    "Intensidad",
  ],
  "season.subtle": ["Subtle", "Мягко", "Жұмсақ", "М’яко", "Dezent", "Suave"],
  "season.normal": [
    "Normal",
    "Обычно",
    "Қалыпты",
    "Звичайно",
    "Normal",
    "Normal",
  ],
  "season.preview": [
    "Preview",
    "Предпросмотр",
    "Алдын ала көрініс",
    "Попередній перегляд",
    "Vorschau",
    "Vista previa",
  ],
  "season.motionHint": [
    "Respects reduced motion and pauses when the app is hidden.",
    "Учитывает уменьшение движения и останавливается в фоне.",
    "Қозғалысты азайту режимін ескеріп, фонда тоқтайды.",
    "Враховує зменшення руху та зупиняється у фоні.",
    "Beachtet reduzierte Bewegung und pausiert im Hintergrund.",
    "Respeta el movimiento reducido y se pausa en segundo plano.",
  ],
};
