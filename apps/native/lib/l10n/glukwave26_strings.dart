import 'package:flutter/widgets.dart';
import 'wave_localizations.dart';

String wave26Text(BuildContext context, String key) {
  final index = ['en','ru','kk','uk','de','es'].indexOf(WaveStrings.of(context).language);
  return _copy[key]?[index < 0 ? 0 : index] ?? key;
}
const _copy = <String,List<String>>{
  "settings.category": ["Settings category", "Раздел настроек", "Параметрлер бөлімі", "Розділ налаштувань", "Einstellungsbereich", "Categoría de ajustes"],
  "settings.search": ["Find a setting", "Найти настройку", "Параметрді табу", "Знайти налаштування", "Einstellung suchen", "Buscar un ajuste"],
  "settings.noResults": ["No matching categories", "Подходящих разделов нет", "Сәйкес бөлімдер жоқ", "Відповідних розділів немає", "Keine passenden Bereiche", "No hay categorías coincidentes"],
  "artist.source": ["Open original profile", "Открыть исходный профиль", "Түпнұсқа профильді ашу", "Відкрити оригінальний профіль", "Originalprofil öffnen", "Abrir perfil original"],
  "artist.empty": ["This source has no tracks available yet.", "На этой площадке пока нет доступных треков.", "Бұл платформада әзірге қолжетімді тректер жоқ.", "На цій платформі поки немає доступних треків.", "Auf dieser Plattform sind noch keine Titel verfügbar.", "Aún no hay canciones disponibles en esta fuente."],
  "artist.playAll": ["Play all", "Слушать всё", "Барлығын тыңдау", "Слухати все", "Alle abspielen", "Reproducir todo"],
  "artist.shuffle": ["Shuffle", "Перемешать", "Араластыру", "Перемішати", "Zufällig", "Aleatorio"],
  "artist.albums": ["Albums", "Альбомы", "Альбомдар", "Альбоми", "Alben", "Álbumes"],
  "artist.playlists": ["Public playlists", "Открытые плейлисты", "Ашық плейлистер", "Відкриті плейлисти", "Öffentliche Playlists", "Listas públicas"],
  "artist.tracks": ["Tracks", "Треки", "Тректер", "Треки", "Titel", "Canciones"],
  "auth.showPassword": ["Show password", "Показать пароль", "Құпиясөзді көрсету", "Показати пароль", "Passwort anzeigen", "Mostrar contraseña"],
  "auth.hidePassword": ["Hide password", "Скрыть пароль", "Құпиясөзді жасыру", "Приховати пароль", "Passwort verbergen", "Ocultar contraseña"],
  "settings.cacheNote": ["Automatic cache keeps a limited set of recently played tracks. Save a track explicitly to keep it for offline listening.", "Автокеш хранит ограниченный набор недавно прослушанных треков. Сохраните трек отдельно, чтобы оставить его для прослушивания без сети.", "Автокеш жақында тыңдалған тректердің шектеулі санын сақтайды. Офлайн тыңдау үшін тректі бөлек сақтаңыз.", "Автокеш зберігає обмежений набір нещодавно прослуханих треків. Збережіть трек окремо для прослуховування без мережі.", "Der automatische Cache enthält eine begrenzte Zahl zuletzt gehörter Titel. Speichere einen Titel ausdrücklich zum Offline-Hören.", "La caché automática guarda una cantidad limitada de canciones recientes. Guarda una canción expresamente para escucharla sin conexión."],
};
