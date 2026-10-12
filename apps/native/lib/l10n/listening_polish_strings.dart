import 'package:flutter/widgets.dart';
import 'wave_localizations.dart';

String polishText(String key, BuildContext context) {
  final index = [
    'en',
    'ru',
    'kk',
    'uk',
    'de',
    'es',
  ].indexOf(WaveStrings.of(context).language);
  return listeningPolishStrings[key]?[index < 0 ? 0 : index] ?? key;
}

const listeningPolishStrings = <String, List<String>>{
  'all': ['All', 'Всё', 'Барлығы', 'Усе', 'Alle', 'Todo'],
  'tracks': ['Tracks', 'Треки', 'Тректер', 'Треки', 'Titel', 'Canciones'],
  'artists': [
    'Artists',
    'Артисты',
    'Орындаушылар',
    'Виконавці',
    'Künstler',
    'Artistas',
  ],
  'playlists': [
    'Playlists',
    'Плейлисты',
    'Плейлистер',
    'Плейлісти',
    'Playlists',
    'Listas',
  ],
  'browse': [
    'Find your next favourite',
    'Найди то, что полюбишь',
    'Жаңа сүйікті әніңді тап',
    'Знайди те, що полюбиш',
    'Entdecke neue Lieblingsmusik',
    'Descubre tu próximo favorito',
  ],
  'browseDetail': [
    'Artists, collections and music for your mood.',
    'Артисты, подборки и музыка под настроение.',
    'Орындаушылар, жинақтар және көңіл күйге сай музыка.',
    'Виконавці, добірки й музика під настрій.',
    'Künstler, Sammlungen und Musik für deine Stimmung.',
    'Artistas, colecciones y música para tu estado de ánimo.',
  ],
  'source': [
    'Music source',
    'Источник музыки',
    'Музыка көзі',
    'Джерело музики',
    'Musikquelle',
    'Fuente de música',
  ],
  'categories': [
    'Explore your music',
    'Открой свою музыку',
    'Музыкаңды аш',
    'Відкрий свою музику',
    'Entdecke deine Musik',
    'Explora tu música',
  ],
  'recent': [
    'Back to your favourites',
    'Вернуться к любимому',
    'Сүйікті әндерге оралу',
    'Повернутися до улюбленого',
    'Zurück zu deinen Favoriten',
    'Vuelve a tus favoritos',
  ],
  'cover': [
    'Cover appearance',
    'Вид обложки',
    'Мұқаба көрінісі',
    'Вигляд обкладинки',
    'Cover-Ansicht',
    'Apariencia de portada',
  ],
  'flat': ['Artwork', 'Обложка', 'Мұқаба', 'Обкладинка', 'Cover', 'Portada'],
  'next': [
    'Up next',
    'Следующая строка',
    'Келесі жол',
    'Наступний рядок',
    'Nächste Zeile',
    'Siguiente línea',
  ],
  'progress': [
    'Track progress',
    'Прогресс трека',
    'Тректің орындалуы',
    'Прогрес треку',
    'Titelfortschritt',
    'Progreso de la canción',
  ],
};
