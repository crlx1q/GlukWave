import 'package:flutter/widgets.dart';
import '../l10n/wave_localizations.dart';

String playlistText(
  BuildContext context,
  String key, [
  Map<String, Object> values = const {},
]) {
  if (key == 'tracks') {
    return WaveStrings.of(
      context,
    ).plural('count.tracks', (values['count'] as num? ?? 0).toInt());
  }
  final language = WaveStrings.of(context).language,
      index = ['en', 'ru', 'kk', 'uk', 'de', 'es'].indexOf(language);
  var text =
      (_copy[key] ?? [key, key, key, key, key, key])[index < 0 ? 0 : index];
  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value.toString());
  }
  return text;
}

const _copy = <String, List<String>>{
  "add": [
    "Add to playlist",
    "В плейлист",
    "Плейлистке қосу",
    "До плейлиста",
    "Zur Playlist",
    "Añadir a playlist",
  ],
  "one": [
    "In {name}",
    "В «{name}»",
    "«{name}» ішінде",
    "У «{name}»",
    "In {name}",
    "En {name}",
  ],
  "many": [
    "In {count} playlists",
    "В {count} плейлистах",
    "{count} плейлистте",
    "У {count} плейлистах",
    "In {count} Playlists",
    "En {count} playlists",
  ],
  "manage": [
    "Your playlists",
    "Твои плейлисты",
    "Сенің плейлисттерің",
    "Твої плейлисти",
    "Deine Playlists",
    "Tus playlists",
  ],
  "find": [
    "Find a playlist",
    "Найти плейлист",
    "Плейлист табу",
    "Знайти плейлист",
    "Playlist finden",
    "Buscar playlist",
  ],
  "saving": [
    "Saving…",
    "Сохраняем…",
    "Сақталуда…",
    "Зберігаємо…",
    "Wird gespeichert…",
    "Guardando…",
  ],
  "retry": [
    "Try again",
    "Повторить",
    "Қайталау",
    "Повторити",
    "Erneut versuchen",
    "Reintentar",
  ],
  "create": [
    "New playlist",
    "Новый плейлист",
    "Жаңа плейлист",
    "Новий плейлист",
    "Neue Playlist",
    "Nueva playlist",
  ],
  "empty": [
    "No playlists yet",
    "Плейлистов пока нет",
    "Әзірге плейлист жоқ",
    "Плейлистів поки немає",
    "Noch keine Playlists",
    "Aún no hay playlists",
  ],
  "noMatch": [
    "Nothing found",
    "Ничего не найдено",
    "Ештеңе табылмады",
    "Нічого не знайдено",
    "Nichts gefunden",
    "Sin resultados",
  ],
  "added": [
    "Added",
    "Добавлено",
    "Қосылды",
    "Додано",
    "Hinzugefügt",
    "Añadido",
  ],
  "addTracks": [
    "Add tracks",
    "Добавить треки",
    "Тректер қосу",
    "Додати треки",
    "Titel hinzufügen",
    "Añadir canciones",
  ],
  "searchTracks": [
    "Find in your library",
    "Найти в медиатеке",
    "Медиатекадан іздеу",
    "Знайти в медіатеці",
    "Mediathek durchsuchen",
    "Buscar en tu biblioteca",
  ],
  "play": [
    "Play all",
    "Слушать всё",
    "Барлығын тыңдау",
    "Слухати все",
    "Alle abspielen",
    "Reproducir todo",
  ],
  "edit": [
    "Edit playlist",
    "Изменить плейлист",
    "Плейлистті өзгерту",
    "Змінити плейлист",
    "Playlist bearbeiten",
    "Editar playlist",
  ],
  "name": ["Name", "Название", "Атауы", "Назва", "Name", "Nombre"],
  "description": [
    "Description",
    "Описание",
    "Сипаттамасы",
    "Опис",
    "Beschreibung",
    "Descripción",
  ],
  "save": ["Save", "Сохранить", "Сақтау", "Зберегти", "Speichern", "Guardar"],
  "delete": [
    "Delete playlist",
    "Удалить плейлист",
    "Плейлистті жою",
    "Видалити плейлист",
    "Playlist löschen",
    "Eliminar playlist",
  ],
  "confirm": [
    "Delete “{name}”? Audio files will not be deleted.",
    "Удалить «{name}»? Аудиофайлы не будут удалены.",
    "«{name}» плейлистін жою керек пе? Аудиофайлдар жойылмайды.",
    "Видалити «{name}»? Аудіофайли не будуть видалені.",
    "„{name}“ löschen? Audiodateien werden nicht gelöscht.",
    "¿Eliminar «{name}»? Los archivos de audio no se eliminarán.",
  ],
  "cancel": [
    "Cancel",
    "Отмена",
    "Бас тарту",
    "Скасувати",
    "Abbrechen",
    "Cancelar",
  ],
  "private": ["Private", "Личный", "Жеке", "Особистий", "Privat", "Privada"],
  "public": [
    "Public",
    "Открытый",
    "Ашық",
    "Відкритий",
    "Öffentlich",
    "Pública",
  ],
  "tracks": [
    "{count} tracks",
    "{count} треков",
    "{count} трек",
    "{count} треків",
    "{count} Titel",
    "{count} canciones",
  ],
  "remove": [
    "Remove from playlist",
    "Убрать из плейлиста",
    "Плейлисттен алып тастау",
    "Прибрати з плейлиста",
    "Aus Playlist entfernen",
    "Quitar de la playlist",
  ],
  "up": [
    "Move up",
    "Поднять выше",
    "Жоғары жылжыту",
    "Підняти вище",
    "Nach oben",
    "Subir",
  ],
  "down": [
    "Move down",
    "Опустить ниже",
    "Төмен жылжыту",
    "Опустити нижче",
    "Nach unten",
    "Bajar",
  ],
};
