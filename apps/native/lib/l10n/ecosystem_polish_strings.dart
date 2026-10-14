import 'package:flutter/widgets.dart';
import 'wave_localizations.dart';

String ecosystemText(String key, BuildContext context) {
  final index = [
    'en',
    'ru',
    'kk',
    'uk',
    'de',
    'es',
  ].indexOf(WaveStrings.of(context).language);
  return ecosystemPolishStrings[key]?[index < 0 ? 0 : index] ?? key;
}

const ecosystemPolishStrings = <String, List<String>>{
  'selectedOutput': [
    'Selected output',
    'Выбранный источник',
    'Таңдалған құрылғы',
    'Вибраний пристрій',
    'Gewählte Ausgabe',
    'Salida seleccionada',
  ],
  'connectScreenOff': [
    'Connect with the screen off',
    'Connect при выключенном экране',
    'Экран өшірулі кездегі Connect',
    'Connect із вимкненим екраном',
    'Connect bei ausgeschaltetem Bildschirm',
    'Connect con la pantalla apagada',
  ],
  'connectScreenOffHint': [
    'Keeps this phone available to your other devices. Uses battery; stop it from the notification anytime.',
    'Сохраняет связь с другими устройствами. Расходует заряд; можно остановить в уведомлении.',
    'Басқа құрылғылармен байланысты сақтайды. Батареяны пайдаланады; хабарландырудан кез келген уақытта тоқтата аласыз.',
    'Зберігає зв’язок з іншими пристроями. Витрачає заряд; можна зупинити в сповіщенні.',
    'Hält die Verbindung zu deinen anderen Geräten. Verbraucht Akku; jederzeit über die Benachrichtigung beenden.',
    'Mantiene la conexión con tus otros dispositivos. Consume batería; puedes detenerlo desde la notificación.',
  ],
  'together': [
    'Listening together',
    'Слушаете вместе',
    'Бірге тыңдап отырсыздар',
    'Слухаєте разом',
    'Gemeinsam hören',
    'Escuchando juntos',
  ],
  'listening': [
    'Listening',
    'Слушает',
    'Тыңдап отыр',
    'Слухає',
    'Hört gerade',
    'Escuchando',
  ],
  'connected': [
    'Connected',
    'Подключён',
    'Қосылды',
    'Підключений',
    'Verbunden',
    'Conectado',
  ],
  'waiting': [
    'Connecting…',
    'Подключаем…',
    'Қосылуда…',
    'Підключаємо…',
    'Verbindung wird hergestellt…',
    'Conectando…',
  ],
  'queueAdd': [
    'Add to queue',
    'Добавить в очередь',
    'Кезекке қосу',
    'Додати до черги',
    'Zur Warteschlange',
    'Añadir a la cola',
  ],
  'queueSearch': [
    'Search your music',
    'Найти музыку',
    'Музыканы іздеу',
    'Знайти музику',
    'Musik suchen',
    'Buscar música',
  ],
  'remove': [
    'Remove from queue',
    'Убрать из очереди',
    'Кезектен алып тастау',
    'Прибрати з черги',
    'Aus Warteschlange entfernen',
    'Quitar de la cola',
  ],
  'up': [
    'Move up',
    'Поднять выше',
    'Жоғары жылжыту',
    'Підняти вище',
    'Nach oben',
    'Subir',
  ],
  'down': [
    'Move down',
    'Опустить ниже',
    'Төмен жылжыту',
    'Опустити нижче',
    'Nach unten',
    'Bajar',
  ],
  'allDevices': [
    'All devices',
    'Все устройства',
    'Барлық құрылғылар',
    'Усі пристрої',
    'Alle Geräte',
    'Todos los dispositivos',
  ],
};
