import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import '../core/models.dart';

String _random([int length = 24]) => base64Url
    .encode(List.generate(length, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
bool lanAddress(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null || address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      b[0] == 192 && b[1] == 168 ||
      b[0] == 172 && b[1] >= 16 && b[1] <= 31;
}

class LanCipher {
  final SecretKey key;
  final String session, side;
  final AesGcm algorithm = AesGcm.with256bits();
  int sent = 0, received = 0;
  LanCipher(this.key, this.session, this.side);
  Future<String> encode(Json message) async {
    final bytes = utf8.encode(jsonEncode(message));
    if (bytes.length > 240000) throw const FormatException('LAN frame limit');
    final sequence = ++sent;
    final box = await algorithm.encrypt(
      bytes,
      secretKey: key,
      aad: utf8.encode('$session:$side:$sequence'),
    );
    return jsonEncode({
      'sequence': sequence,
      'box': base64Url.encode(box.concatenation()),
    });
  }

  Future<Json> decode(String frame) async {
    if (frame.length > 350000) throw const FormatException('LAN frame limit');
    final envelope = object(jsonDecode(frame)), sequence = envelope['sequence'];
    if (sequence is! int ||
        sequence != received + 1 ||
        envelope['box'] is! String) {
      throw const FormatException('LAN replay');
    }
    final bytes = base64Url.decode(envelope['box'] as String);
    final plain = await algorithm.decrypt(
      SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16),
      secretKey: key,
      aad: utf8.encode(
        '$session:${side == 'host' ? 'client' : 'host'}:$sequence',
      ),
    );
    final result = object(jsonDecode(utf8.decode(plain)));
    received = sequence;
    return result;
  }
}

class _LanChannel {
  final WebSocket socket;
  final LanCipher cipher;
  final Json peer;
  final Map<String, Completer<Json>> pending = {};
  Future<void> writes = Future.value();
  bool closed = false;
  int inflight = 0;
  _LanChannel(this.socket, this.cipher, this.peer);
  Future<void> send(Json value) {
    final result = writes.then((_) async {
      if (closed) throw const SocketException('LAN disconnected');
      socket.add(await cipher.encode(value));
    });
    writes = result.catchError((_) {});
    return result;
  }

  Future<Json> request(String command, Json arguments) async {
    if (pending.length >= 16) throw const SocketException('LAN busy');
    final id = _random(12), completer = Completer<Json>();
    pending[id] = completer;
    try {
      await send({
        'type': 'request',
        'id': id,
        'command': command,
        'arguments': arguments,
      });
      return await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      pending.remove(id);
    }
  }

  void close() {
    if (closed) return;
    closed = true;
    for (final value in pending.values) {
      if (!value.isCompleted) {
        value.completeError(const SocketException('LAN disconnected'));
      }
    }
    pending.clear();
    unawaited(socket.close());
  }
}

/// A native device is its own LAN host. No cloud bearer token is transported.
/// Pairing keys arrive out of band in a short-lived QR invitation; every frame
/// uses a fresh session-derived AEAD key, directional sequence and authentication.
class LanTransport {
  final String account, deviceId, name, kind;
  final int maximumPeers;
  final Future<Json> Function(String command, Json arguments, String peerId)
  command;
  final Future<void> Function(Json state) state;
  final void Function() changed;
  final Future<void> Function(Json trust) persist;
  final Json trust;
  final Map<String, _LanChannel> _channels = {};
  final Set<WebSocket> _handshakes = {};
  Json? _invitation;
  HttpServer? _server;
  _LanChannel? _host;
  String? hostName, hostId, lastError;
  String? _reconnectEndpoint;
  Timer? _reconnect;
  bool _closed = false, _joining = false;
  LanTransport({
    required this.account,
    required this.deviceId,
    required this.name,
    required this.kind,
    required this.command,
    required this.state,
    required this.changed,
    required this.persist,
    Json? trusted,
    this.maximumPeers = 3,
  }) : trust = trusted ?? {};
  bool get enabled => _server != null;
  bool get hosting => _host == null && hostId == null;
  bool get connected => _host != null;
  List<Json> get peers => trust.entries
      .map(
        (entry) => {
          'id': entry.key,
          'name': object(entry.value)['name'],
          'kind': object(entry.value)['kind'],
          'trusted': true,
          'online':
              _channels.containsKey(entry.key) ||
              _host?.peer['id'] == entry.key,
          'status':
              _channels.containsKey(entry.key) || _host?.peer['id'] == entry.key
              ? 'online'
              : _joining
              ? 'connecting'
              : 'offline',
          'lastSeen': object(entry.value)['lastSeen'],
        },
      )
      .toList();
  Future<void> start({InternetAddress? address, int port = 43219}) async {
    if (_server != null) return;
    _closed = false;
    try {
      _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    } on SocketException {
      if (port == 0) rethrow;
      _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, 0);
    }
    _server!.listen((request) async {
      if (_closed ||
          _handshakes.length >= 4 ||
          request.uri.path != '/lan' ||
          request.headers.value('origin') != null ||
          !lanAddress(request.connectionInfo?.remoteAddress.address ?? '') ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      WebSocket? socket;
      try {
        socket = await WebSocketTransformer.upgrade(request);
        socket.pingInterval = const Duration(seconds: 8);
        _handshakes.add(socket);
        await _accept(socket);
      } catch (_) {
        await socket?.close();
      } finally {
        if (socket != null) _handshakes.remove(socket);
      }
    });
    changed();
  }

  Future<String> invite() async {
    await start();
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final address =
        interfaces
            .expand((value) => value.addresses)
            .where((value) => !value.isLoopback && lanAddress(value.address))
            .firstOrNull
            ?.address ??
        '127.0.0.1';
    _invitation = {
      'id': _random(12),
      'secret': _random(32),
      'expiresAt': DateTime.now().millisecondsSinceEpoch + 120000,
    };
    return Uri(
      scheme: 'glukwave',
      host: 'lan',
      queryParameters: {
        'data': base64Url.encode(
          utf8.encode(
            jsonEncode({
              ..._invitation!,
              'endpoint': 'ws://$address:${_server!.port}/lan',
              'account': account,
              'deviceId': deviceId,
              'name': name,
              'kind': kind,
            }),
          ),
        ),
      },
    ).toString();
  }

  static Json invitation(String value, {int? now}) {
    final uri = Uri.parse(value.trim());
    if (uri.scheme != 'glukwave' || uri.host != 'lan' || value.length > 3000) {
      throw const FormatException('LAN invitation');
    }
    final result = object(
      jsonDecode(
        utf8.decode(base64Url.decode(uri.queryParameters['data'] ?? '')),
      ),
    );
    for (final key in ['account', 'deviceId', 'id', 'name', 'kind']) {
      if (result[key] is! String ||
          (result[key] as String).isEmpty ||
          (result[key] as String).length > 100) {
        throw const FormatException('LAN invitation');
      }
    }
    final endpoint = Uri.parse(result['endpoint'] as String? ?? '');
    if (endpoint.scheme != 'ws' ||
        !lanAddress(endpoint.host) ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.path != '/lan' ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.port < 1 ||
        endpoint.port > 65535 ||
        (result['expiresAt'] as num? ?? 0) <
            (now ?? DateTime.now().millisecondsSinceEpoch) ||
        (result['secret'] is! String) ||
        base64Url
                .decode(base64Url.normalize(result['secret'] as String))
                .length !=
            32) {
      throw const FormatException('LAN invitation');
    }
    return result;
  }

  Future<void> join(String value) async {
    if (_channels.isNotEmpty) throw StateError('busy');
    final info = invitation(value);
    if (info['account'] != account || info['deviceId'] == deviceId) {
      throw const FormatException('LAN account');
    }
    if (!trust.containsKey(info['deviceId']) &&
        trust.length >= maximumPeers - 1) {
      throw StateError('limit');
    }
    await start();
    await disconnect();
    await _join(
      info['endpoint'] as String,
      info['deviceId'] as String,
      info['secret'] as String,
      invitationId: info['id'] as String,
    );
  }

  Future<SecretKey> _key(
    String secret,
    String clientNonce,
    String hostNonce,
    String host,
    String peer,
  ) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(base64Url.decode(base64Url.normalize(secret))),
    nonce: utf8.encode('$clientNonce:$hostNonce'),
    info: utf8.encode('glukwave-lan-v1:$account:$host:$peer'),
  );
  Future<void> _accept(WebSocket socket) async {
    final iterator = StreamIterator<dynamic>(socket);
    if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) return;
    final hello = _plain(iterator.current),
        peer = hello['deviceId'] as String? ?? '';
    if (peer.isEmpty ||
        peer.length > 80 ||
        peer == deviceId ||
        hello['account'] != account ||
        hello['nonce'] is! String ||
        hosting == false) {
      throw const FormatException('LAN handshake');
    }
    final saved = object(trust[peer]);
    String? secret = saved['secret'] as String?;
    final invitation = _invitation;
    final newPair = secret == null;
    if (newPair) {
      if (invitation == null ||
          hello['invitation'] != invitation['id'] ||
          (invitation['expiresAt'] as int) <
              DateTime.now().millisecondsSinceEpoch ||
          trust.length >= maximumPeers - 1) {
        throw const FormatException('LAN pairing');
      }
      secret = invitation['secret'] as String;
    }
    final hostNonce = _random(), session = _random();
    socket.add(
      jsonEncode({
        'nonce': hostNonce,
        'session': session,
        'deviceId': deviceId,
        'account': account,
        'name': name,
        'kind': kind,
      }),
    );
    final cipher = LanCipher(
      await _key(secret, hello['nonce'] as String, hostNonce, deviceId, peer),
      session,
      'host',
    );
    if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) return;
    final proof = await cipher.decode(iterator.current as String);
    if (proof['type'] != 'proof' || proof['deviceId'] != peer) {
      throw const FormatException('LAN proof');
    }
    if (newPair &&
        (!identical(_invitation, invitation) ||
            trust.length >= maximumPeers - 1 ||
            (invitation!['expiresAt'] as int) <
                DateTime.now().millisecondsSinceEpoch)) {
      throw const FormatException('LAN pairing');
    }
    if (!newPair && object(trust[peer])['secret'] != secret) {
      throw const FormatException('LAN revoked');
    }
    final identity = {
      'id': peer,
      'name': (hello['name'] as String? ?? 'GlukWave').substring(
        0,
        min(80, (hello['name'] as String? ?? 'GlukWave').length),
      ),
      'kind': hello['kind'] == 'windows' ? 'windows' : 'android',
    };
    if (newPair) {
      _invitation = null;
      trust[peer] = {
        ...identity,
        'secret': secret,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      };
      await persist(trust);
    }
    final channel = _LanChannel(socket, cipher, identity);
    _channels.remove(peer)?.close();
    _channels[peer] = channel;
    await channel.send({'type': 'paired', 'deviceId': deviceId});
    changed();
    unawaited(_listen(channel, iterator));
  }

  Json _plain(dynamic value) {
    if (value is! String || value.length > 2048) {
      throw const FormatException('LAN hello');
    }
    return object(jsonDecode(value));
  }

  Future<void> _join(
    String endpoint,
    String id,
    String secret, {
    String? invitationId,
  }) async {
    if (_joining || _closed) return;
    _joining = true;
    changed();
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        endpoint,
      ).timeout(const Duration(seconds: 5));
      socket.pingInterval = const Duration(seconds: 8);
      final iterator = StreamIterator<dynamic>(socket), nonce = _random();
      socket.add(
        jsonEncode({
          'deviceId': deviceId,
          'account': account,
          'name': name,
          'kind': kind,
          'nonce': nonce,
          if (invitationId != null) 'invitation': invitationId,
        }),
      );
      if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        throw const SocketException('LAN handshake');
      }
      final hello = _plain(iterator.current);
      if (hello['deviceId'] != id || hello['account'] != account) {
        throw const FormatException('LAN identity');
      }
      final cipher = LanCipher(
        await _key(secret, nonce, hello['nonce'] as String, id, deviceId),
        hello['session'] as String,
        'client',
      );
      final channel = _LanChannel(socket, cipher, {
        'id': id,
        'name': hello['name'],
        'kind': hello['kind'],
      });
      await channel.send({'type': 'proof', 'deviceId': deviceId});
      if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        throw const SocketException('LAN pairing');
      }
      final paired = await cipher.decode(iterator.current as String);
      if (paired['type'] != 'paired') {
        throw const FormatException('LAN pairing');
      }
      trust[id] = {
        'id': id,
        'name': hello['name'],
        'kind': hello['kind'],
        'secret': secret,
        'endpoint': endpoint,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      };
      await persist(trust);
      _host = channel;
      hostId = id;
      hostName = hello['name'] as String?;
      _reconnectEndpoint = endpoint;
      lastError = null;
      unawaited(_listen(channel, iterator));
    } catch (_) {
      await socket?.close();
      lastError = 'network';
      rethrow;
    } finally {
      _joining = false;
      changed();
    }
  }

  Future<void> _listen(
    _LanChannel channel,
    StreamIterator<dynamic> iterator,
  ) async {
    try {
      while (await iterator.moveNext()) {
        final packet = await channel.cipher.decode(iterator.current as String),
            type = packet['type'];
        if (type == 'response') {
          final completer = channel.pending[packet['id']];
          if (completer != null && !completer.isCompleted) {
            if (packet['error'] != null) {
              completer.completeError(StateError(packet['error'].toString()));
            } else {
              completer.complete(object(packet['result']));
            }
          }
        } else if (type == 'request') {
          final id = packet['id'];
          if (id is! String || id.length > 80) {
            throw const FormatException('LAN request');
          }
          if (channel.inflight >= 16) {
            throw const FormatException('LAN request limit');
          }
          channel.inflight++;
          // Keep decoding replies while a command forwards to this same peer.
          // The controller serializes playback mutations, not the socket reader.
          unawaited(_respond(channel, id, packet));
        } else if (type == 'revoked') {
          trust.remove(channel.peer['id']);
          await persist(trust);
          if (identical(channel, _host)) {
            hostId = null;
            hostName = null;
            _reconnectEndpoint = null;
            _reconnect?.cancel();
          }
          break;
        } else if (type == 'state' && identical(channel, _host)) {
          await state(object(packet['state']));
        }
      }
    } catch (_) {
      lastError = 'network';
    } finally {
      channel.close();
      final id = channel.peer['id'] as String;
      if (identical(_channels[id], channel)) _channels.remove(id);
      if (identical(_host, channel)) {
        _host = null;
        lastError = 'network';
        _scheduleReconnect();
      }
      changed();
    }
  }

  Future<void> _respond(_LanChannel channel, String id, Json packet) async {
    try {
      final result = await command(
        packet['command'] as String,
        object(packet['arguments']),
        channel.peer['id'] as String,
      );
      await channel.send({'type': 'response', 'id': id, 'result': result});
    } catch (error) {
      try {
        await channel.send({
          'type': 'response',
          'id': id,
          'error': error is StateError ? error.message : 'network',
        });
      } catch (_) {}
    } finally {
      channel.inflight--;
    }
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    if (_closed || hostId == null || _reconnectEndpoint == null) return;
    _reconnect = Timer(const Duration(seconds: 3), () async {
      try {
        final secret = object(trust[hostId])['secret'] as String?;
        if (secret != null) await _join(_reconnectEndpoint!, hostId!, secret);
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Future<Json> request(String command, Json arguments, {String? peerId}) async {
    final channel = peerId == null ? _host : _channels[peerId];
    if (channel == null) throw const SocketException('LAN disconnected');
    return channel.request(command, arguments);
  }

  Future<void> broadcast(Json snapshot) async {
    if (!hosting) return;
    await Future.wait(
      _channels.values.toList().map(
        (channel) => channel
            .send({'type': 'state', 'state': snapshot})
            .catchError((_) {}),
      ),
    );
  }

  Future<void> remove(String id) async {
    final peer = _host?.peer['id'] == id ? _host : _channels[id];
    try {
      await peer?.send({'type': 'revoked'});
    } catch (_) {}
    if (_host?.peer['id'] == id) await disconnect();
    _channels.remove(id)?.close();
    trust.remove(id);
    await persist(trust);
    changed();
  }

  Future<void> disconnect() async {
    hostId = null;
    hostName = null;
    _reconnectEndpoint = null;
    _reconnect?.cancel();
    _host?.close();
    _host = null;
    changed();
  }

  Future<void> close() async {
    _closed = true;
    await disconnect();
    _invitation = null;
    for (final channel in _channels.values.toList()) {
      channel.close();
    }
    _channels.clear();
    for (final socket in _handshakes.toList()) {
      await socket.close();
    }
    _handshakes.clear();
    await _server?.close(force: true);
    _server = null;
    changed();
  }
}
