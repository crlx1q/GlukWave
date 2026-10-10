import 'package:flutter/widgets.dart';
import 'wave_localizations.dart';

String lt(BuildContext context, String key) =>
    lyricsLabel(WaveStrings.of(context).language, key);
String lyricsLabel(String language, String key) {
  final index = ['en', 'ru', 'kk', 'uk', 'de', 'es'].indexOf(language);
  return _strings[key]?[index < 0 ? 0 : index] ?? key;
}

const _strings = <String, List<String>>{
  "lyrics.draftHelp": [
    "Edit the preview, then save it to this track.",
    "Отредактируй текст и сохрани его для этого трека.",
    "Мәтінді өңдеп, осы трекке сақта.",
    "Відредагуй текст і збережи його для цього треку.",
    "Bearbeite die Vorschau und speichere sie für diesen Titel.",
    "Edita la vista previa y guárdala para esta canción.",
  ],
  'lyrics.file': [
    'Import .txt or .lrc',
    'Импорт .txt или .lrc',
    '.txt не .lrc импорттау',
    'Імпорт .txt або .lrc',
    '.txt oder .lrc importieren',
    'Importar .txt o .lrc',
  ],
  'lyrics.fileTooLarge': [
    'Choose a text file smaller than 200 KB.',
    'Выбери текстовый файл до 200 КБ.',
    '200 КБ-тан кіші мәтін файлын таңда.',
    'Вибери текстовий файл до 200 КБ.',
    'Wähle eine Textdatei unter 200 KB.',
    'Elige un archivo de texto de menos de 200 KB.',
  ],

  "lyrics.source": [
    "Lyrics source",
    "Источник текста",
    "Мәтін көзі",
    "Джерело тексту",
    "Textquelle",
    "Fuente de la letra",
  ],
  "lyrics.geniusUrl": [
    "Genius lyrics link",
    "Ссылка на текст в Genius",
    "Genius мәтініне сілтеме",
    "Посилання на текст у Genius",
    "Link zum Genius-Songtext",
    "Enlace de la letra en Genius",
  ],
  "lyrics.geniusPreview": [
    "Load preview",
    "Загрузить предпросмотр",
    "Алдын ала қарау",
    "Завантажити попередній перегляд",
    "Vorschau laden",
    "Cargar vista previa",
  ],
  "lyrics.geniusLoading": [
    "Loading lyrics…",
    "Загружаем текст…",
    "Мәтін жүктелуде…",
    "Завантажуємо текст…",
    "Songtext wird geladen…",
    "Cargando letra…",
  ],
  "lyrics.geniusHelp": [
    "Genius provides plain text. Add line timestamps manually if you want synchronized lyrics. Nothing is saved until you choose Save.",
    "Genius предоставляет обычный текст. Для синхронизации добавь время строк вручную. Текст сохранится только после нажатия «Сохранить».",
    "Genius жай мәтінді ұсынады. Синхрондау үшін жолдардың уақытын қолмен қос. «Сақтау» түймесін басқанша мәтін сақталмайды.",
    "Genius надає звичайний текст. Для синхронізації додай час рядків вручну. Текст збережеться лише після натискання «Зберегти».",
    "Genius liefert Text ohne Zeitmarken. Für synchronisierte Zeilen kannst du die Zeiten selbst ergänzen. Erst mit Speichern wird der Text übernommen.",
    "Genius ofrece texto sin tiempos. Añade las marcas de tiempo manualmente para sincronizarlo. Nada se guarda hasta que pulses Guardar.",
  ],
  "lyrics.geniusInvalid": [
    "Use an HTTPS link to a lyrics page on genius.com.",
    "Вставь HTTPS-ссылку на страницу текста на genius.com.",
    "genius.com мәтін бетінің HTTPS сілтемесін енгіз.",
    "Встав HTTPS-посилання на сторінку тексту на genius.com.",
    "Verwende einen HTTPS-Link zu einer Songtextseite auf genius.com.",
    "Usa un enlace HTTPS a una página de letra en genius.com.",
  ],
  "lyrics.geniusCredit": [
    "Preview from Genius",
    "Предпросмотр из Genius",
    "Genius-тен алдын ала қарау",
    "Попередній перегляд із Genius",
    "Vorschau von Genius",
    "Vista previa de Genius",
  ],
  "lyrics.geniusOriginal": [
    "Original lyrics page",
    "Оригинальная страница",
    "Түпнұсқа мәтін беті",
    "Оригінальна сторінка",
    "Originalseite",
    "Página original",
  ],
  "lyrics.saving": [
    "Saving…",
    "Сохраняем…",
    "Сақталуда…",
    "Зберігаємо…",
    "Wird gespeichert…",
    "Guardando…",
  ],
  "lyrics.scopeChanged": [
    "This track or account changed. Close this editor and open it again.",
    "Трек или аккаунт изменился. Закрой редактор и открой его заново.",
    "Трек не аккаунт өзгерді. Редакторды жауып, қайта аш.",
    "Трек або акаунт змінився. Закрий редактор і відкрий знову.",
    "Der Titel oder das Konto wurde geändert. Schließe den Editor und öffne ihn erneut.",
    "La canción o la cuenta ha cambiado. Cierra el editor y vuelve a abrirlo.",
  ],
};
