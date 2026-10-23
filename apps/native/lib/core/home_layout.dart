import 'models.dart';

const homeCanvasTypes = {
  'wave',
  'playlists',
  'recent',
  'recommendations',
  'discovery',
  'popular',
  'daily',
  'likes',
  'playlist',
  'mix',
};
const homeCanvasSingletons = {
  'wave',
  'playlists',
  'recent',
  'recommendations',
  'discovery',
  'popular',
  'daily',
};
const homeCanvasSizes = ['small', 'medium', 'large'];
const homeCanvasViews = ['cards', 'list', 'compact'];
const homeCanvasMoods = {
  'personal',
  'energy',
  'happy',
  'calm',
  'sad',
  'focus',
  'dream',
};

/// Device-independent settings: ordering and logical spans, never screen pixels.
/// Missing/null settings use the original music hierarchy without a migration
/// write. Legacy pins remain optional destinations below Wave and playlists.
List<Json> defaultHomeCanvas([List<Json> pins = const []]) {
  final result = <Json>[
    {'id': 'wave', 'type': 'wave', 'size': 'large', 'view': 'cards'},
    {'id': 'playlists', 'type': 'playlists', 'size': 'large', 'view': 'cards'},
  ];
  final ids = {
    'wave',
    'playlists',
    'recent',
    'recommendations',
    'discovery',
    'popular',
  };
  for (final indexed in pins.indexed) {
    final pin = indexed.$2;
    if (!{'likes', 'playlist', 'mix'}.contains(pin['type'])) continue;
    var suffix = '${pin['id']}'.replaceAll(RegExp(r'[^\w-]'), '-');
    if (suffix.length > 60) suffix = suffix.substring(0, 60);
    final id = 'pin-${indexed.$1}-$suffix';
    ids.add(id);
    result.add({
      'id': id,
      'type': pin['type'],
      'size': 'small',
      'view': 'compact',
      if (pin['type'] == 'playlist') 'playlistId': pin['playlistId'],
      if (pin['type'] == 'mix') ...{
        'genre': pin['genre'],
        'mood': pin['mood'] ?? 'personal',
      },
    });
    if (result.length == 14) break;
  }
  for (final type in ['recent', 'recommendations', 'discovery', 'popular']) {
    result.add({'id': type, 'type': type, 'size': 'large', 'view': 'cards'});
  }
  return result;
}

/// Mirrors the public settings contract; corrupt cached layouts cannot crash
/// rendering or accidentally revive a deleted/private playlist destination.
List<Json> resolveHomeCanvas(
  dynamic value, {
  List<Json> pins = const [],
  Set<String>? ownedPlaylists,
}) {
  if (value == null) return defaultHomeCanvas(pins);
  final layout = object(value);
  if (layout['version'] != 1 || layout['widgets'] is! List) {
    return defaultHomeCanvas(pins);
  }
  final result = <Json>[], ids = <String>{}, singletons = <String>{};
  for (final raw in layout['widgets'] as List) {
    if (result.length == 20) break;
    final item = object(raw), id = item['id'], type = item['type'];
    if (id is! String ||
        !RegExp(r'^[\w-]{1,80}$').hasMatch(id) ||
        ids.contains(id) ||
        !homeCanvasTypes.contains(type) ||
        !homeCanvasSizes.contains(item['size']) ||
        !homeCanvasViews.contains(item['view'])) {
      continue;
    }
    if (homeCanvasSingletons.contains(type) && singletons.contains(type)) {
      continue;
    }
    if (type == 'playlist' &&
        (item['playlistId'] is! String ||
            (item['playlistId'] as String).isEmpty)) {
      continue;
    }
    if (type == 'mix' &&
        (item['genre'] is! String ||
            (item['genre'] as String).trim().isEmpty ||
            (item['genre'] as String).trim().length > 40 ||
            !homeCanvasMoods.contains(item['mood']))) {
      continue;
    }
    ids.add(id);
    if (homeCanvasSingletons.contains(type)) singletons.add(type);
    result.add({
      'id': id,
      'type': type,
      'size': item['size'],
      'view': item['view'],
      if (type == 'playlist') 'playlistId': item['playlistId'],
      if (type == 'mix') ...{
        'genre': (item['genre'] as String).trim(),
        'mood': item['mood'],
      },
    });
  }
  return result.isEmpty && (layout['widgets'] as List).isNotEmpty
      ? defaultHomeCanvas(pins)
      : result;
}

Json homeCanvasSettings(List<Json> widgets) => {
  'version': 1,
  'widgets': widgets.map((item) => Json.of(item)).toList(),
};

/// Small = third on a wide canvas, half on a phone; medium = half/full;
/// large = full. The width is resolved at render time on each device.
double homeCanvasWidth(double width, String size, {double gap = 16}) {
  if (size == 'large') return width;
  if (width >= 850) {
    return (width - gap * (size == 'small' ? 2 : 1)) /
        (size == 'small' ? 3 : 2);
  }
  if (size == 'small') return (width - gap) / 2;
  return width;
}
