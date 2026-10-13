import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'device_labels.dart';
import 'listening_presence.dart';

String roomDirectoryText(BuildContext context, String key) {
  const values = {
    'ru': {
      'mine': 'Мои комнаты',
      'open': 'Открытые комнаты',
      'moderation': 'Модерация комнат',
      'here': 'Ты здесь',
      'owner': 'Твоя комната',
      'participant': 'Участник',
      'join': 'Присоединиться',
      'listening': 'слушают',
      'online': 'в сети',
      'public': 'Открытая',
      'private': 'Приватная',
      'empty': 'Пока никто не слушает',
      'delete': 'Удалить комнату',
    },
    'en': {
      'mine': 'My rooms',
      'open': 'Open rooms',
      'moderation': 'Room moderation',
      'here': 'You are here',
      'owner': 'Your room',
      'participant': 'Participant',
      'join': 'Join',
      'listening': 'listening',
      'online': 'online',
      'public': 'Public',
      'private': 'Private',
      'empty': 'Nobody is listening yet',
      'delete': 'Delete room',
    },
    'de': {
      'mine': 'Meine Räume',
      'open': 'Öffentliche Räume',
      'moderation': 'Raumverwaltung',
      'here': 'Du bist hier',
      'owner': 'Dein Raum',
      'participant': 'Teilnehmer',
      'join': 'Beitreten',
      'listening': 'hören zu',
      'online': 'online',
      'public': 'Öffentlich',
      'private': 'Privat',
      'empty': 'Noch hört niemand zu',
      'delete': 'Raum löschen',
    },
    'es': {
      'mine': 'Mis salas',
      'open': 'Salas públicas',
      'moderation': 'Moderación de salas',
      'here': 'Estás aquí',
      'owner': 'Tu sala',
      'participant': 'Participante',
      'join': 'Unirse',
      'listening': 'escuchando',
      'online': 'en línea',
      'public': 'Pública',
      'private': 'Privada',
      'empty': 'Aún nadie escucha',
      'delete': 'Eliminar sala',
    },
    'uk': {
      'mine': 'Мої кімнати',
      'open': 'Відкриті кімнати',
      'moderation': 'Модерація кімнат',
      'here': 'Ти тут',
      'owner': 'Твоя кімната',
      'participant': 'Учасник',
      'join': 'Приєднатися',
      'listening': 'слухають',
      'online': 'у мережі',
      'public': 'Відкрита',
      'private': 'Приватна',
      'empty': 'Поки ніхто не слухає',
      'delete': 'Видалити кімнату',
    },
    'kk': {
      'mine': 'Менің бөлмелерім',
      'open': 'Ашық бөлмелер',
      'moderation': 'Бөлмелерді басқару',
      'here': 'Сен осындасың',
      'owner': 'Сенің бөлмең',
      'participant': 'Қатысушы',
      'join': 'Қосылу',
      'listening': 'тыңдап отыр',
      'online': 'желіде',
      'public': 'Ашық',
      'private': 'Жеке',
      'empty': 'Әзірге ешкім тыңдамайды',
      'delete': 'Бөлмені жою',
    },
  };
  return (values[Localizations.localeOf(context).languageCode] ??
          values['en']!)[key] ??
      key;
}

class RoomDirectory extends StatefulWidget {
  final WaveController controller;
  const RoomDirectory({super.key, required this.controller});
  @override
  State<RoomDirectory> createState() => _RoomDirectoryState();
}

class _RoomDirectoryState extends State<RoomDirectory> {
  WaveController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    controller.addListener(refresh);
    controller.openRoomDirectory();
  }

  @override
  void didUpdateWidget(RoomDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(refresh);
      oldWidget.controller.closeRoomDirectory();
      controller.addListener(refresh);
      controller.openRoomDirectory();
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(refresh);
    controller.closeRoomDirectory();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      controller.tell(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller,
        mine = <String, Json>{
          for (final room in c.rooms)
            if (room['ownerId'] == c.user?.id ||
                objects(room['members']).any((m) => m['userId'] == c.user?.id))
              room['id'].toString(): room,
        };
    if (c.room != null) mine[c.room!['id'].toString()] = c.room!;
    Widget group(String label, List<Json> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 12),
          child: Text(
            roomDirectoryText(context, label),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        for (final room in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RoomDiscoveryCard(
              controller: c,
              room: room,
              onJoin: () => run(() => c.enterRoom(room)),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mine.isNotEmpty) group('mine', mine.values.toList()),
        if (c.publicRooms.isNotEmpty)
          group(
            'open',
            c.publicRooms
                .map((room) => room['id'] == c.room?['id'] ? c.room! : room)
                .toList(),
          ),
        if (c.nextPublicRoomOffset != null)
          TextButton.icon(
            onPressed: c.roomDirectoryLoading
                ? null
                : () => run(() => c.refreshRoomDirectory(morePublic: true)),
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(
              Localizations.localeOf(context).languageCode == 'ru'
                  ? 'Показать ещё'
                  : 'Show more',
            ),
          ),
        if (c.user?.admin == true && c.moderationRooms.isNotEmpty)
          group('moderation', c.moderationRooms),
        if (c.user?.admin == true && c.nextModerationRoomOffset != null)
          TextButton.icon(
            onPressed: c.roomDirectoryLoading
                ? null
                : () => run(() => c.refreshRoomDirectory(moreModeration: true)),
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(
              Localizations.localeOf(context).languageCode == 'ru'
                  ? 'Показать ещё'
                  : 'Show more',
            ),
          ),
      ],
    );
  }
}

class RoomDiscoveryCard extends StatelessWidget {
  final WaveController controller;
  final Json room;
  final VoidCallback onJoin;
  const RoomDiscoveryCard({
    super.key,
    required this.controller,
    required this.room,
    required this.onJoin,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller,
        v = waveVisuals(context),
        here = c.room?['id'] == room['id'],
        members = objects(room['members']);
    final current = object(room['currentTrack']), state = object(room['state']);
    final listening =
        (room['listeningCount'] as num?)?.toInt() ??
        members.where(memberListening).length;
    final online =
        (room['onlineCount'] as num?)?.toInt() ??
        members.where((m) => m['online'] == true).length;
    final count = (room['memberCount'] as num?)?.toInt() ?? members.length;
    final track = current.isEmpty ? null : WaveTrack(current);
    return Container(
      key: Key('room-card-${room['id']}'),
      decoration: BoxDecoration(
        color: here ? v.accentSoft : v.surface,
        border: Border.all(color: here ? v.accent : v.line),
        borderRadius: BorderRadius.circular(v.corners(22)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(
                controller: c,
                url: track?.artwork,
                size: 66,
                radius: 14,
                icon: Icons.headphones_outlined,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room['name']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${roomDirectoryText(context, room['visibility'] == 'public' ? 'public' : 'private')} · ${roomDirectoryText(context, room['ownerId'] == c.user?.id ? 'owner' : 'participant')}',
                      style: TextStyle(fontSize: 11, color: v.muted),
                    ),
                    if (here)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          roomDirectoryText(context, 'here'),
                          key: const Key('current-room-highlight'),
                          style: TextStyle(
                            color: v.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (c.user?.admin == true || room['ownerId'] == c.user?.id)
                PopupMenuButton<String>(
                  tooltip: roomDirectoryText(context, 'moderation'),
                  onSelected: (_) async {
                    final confirmed = await showWaveDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: Text(roomDirectoryText(context, 'delete')),
                        content: Text(room['name']?.toString() ?? ''),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: Text(
                              wt('native.0ec753be8d', context: dialog),
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: Text(roomDirectoryText(context, 'delete')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      try {
                        await c.deleteRoom(room);
                      } catch (error) {
                        c.tell(error.toString());
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(roomDirectoryText(context, 'delete')),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              ListeningWave(
                playing: state['playing'] != false && listening > 0,
                size: 17,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  track == null
                      ? roomDirectoryText(context, 'empty')
                      : '${track.title} · ${track.artist}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: track == null ? v.muted : v.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              SizedBox(
                width: members.take(3).length * 22.0 + 9,
                height: 31,
                child: Stack(
                  children: [
                    for (var i = 0; i < members.take(3).length; i++)
                      Positioned(
                        left: i * 22.0,
                        child: ClipOval(
                          child: Artwork(
                            controller: c,
                            url: members[i]['avatarUrl']?.toString(),
                            size: 31,
                            radius: 0,
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (count > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Text(
                    '+${count - 3}',
                    style: TextStyle(
                      color: v.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$listening ${roomDirectoryText(context, 'listening')} · $online ${roomDirectoryText(context, 'online')}',
                  style: TextStyle(fontSize: 11, color: v.muted),
                ),
              ),
              if (!here)
                IconButton.filledTonal(
                  onPressed: onJoin,
                  tooltip: roomDirectoryText(context, 'join'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
