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
