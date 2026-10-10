import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/lan_transport.dart';

String loopback(String invitation) {
  final uri = Uri.parse(invitation), data = LanTransport.invitation(invitation);
  data['endpoint'] = Uri.parse(
    data['endpoint'] as String,
  ).replace(host: '127.0.0.1').toString();
  return uri
      .replace(
        queryParameters: {
          'data': base64Url.encode(utf8.encode(jsonEncode(data))),
        },
      )
      .toString();
}

Future<void> eventually(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('LAN condition timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test(
    'AEAD authenticates direction, sequence, session and refuses replay',
    () async {
      final key = SecretKey(List.generate(32, (i) => i));
      final sender = LanCipher(key, 'session-a', 'host'),
          receiver = LanCipher(key, 'session-a', 'client');
      final frame = await sender.encode({'track': 'original', 'playing': true});
      expect(frame, isNot(contains('original')));
      expect(await receiver.decode(frame), {
        'track': 'original',
        'playing': true,
      });
      await expectLater(receiver.decode(frame), throwsFormatException);
      await expectLater(
        LanCipher(key, 'session-b', 'client').decode(frame),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await expectLater(
        LanCipher(key, 'session-a', 'host').decode(frame),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final packet = object(jsonDecode(frame)),
          bytes = base64Url.decode(packet['box'] as String);
      bytes[15] ^= 1;
      packet['box'] = base64Url.encode(bytes);
      await expectLater(
        LanCipher(key, 'session-a', 'client').decode(jsonEncode(packet)),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );
  test('Invitations reject public origins, invalid keys and expiry', () {
    expect(lanAddress('192.168.3.7'), true);
    expect(lanAddress('172.31.2.2'), true);
    expect(lanAddress('8.8.8.8'), false);
    expect(lanAddress('172.32.0.1'), false);
    expect(lanAddress('example.com'), false);
    final info = {
      'endpoint': 'ws://192.168.3.7:43219/lan',
      'account': 'own',
      'deviceId': 'pc',
      'id': 'invite',
      'name': 'PC',
      'kind': 'windows',
      'secret': base64Url.encode(List.filled(32, 1)),
      'expiresAt': DateTime.now().millisecondsSinceEpoch - 1,
    };
    String encode() => Uri(
      scheme: 'glukwave',
      host: 'lan',
      queryParameters: {
        'data': base64Url.encode(utf8.encode(jsonEncode(info))),
      },
    ).toString();
    expect(() => LanTransport.invitation(encode()), throwsFormatException);
    info['expiresAt'] = DateTime.now().millisecondsSinceEpoch + 60000;
    info['endpoint'] = 'ws://8.8.8.8:43219/lan';
    expect(() => LanTransport.invitation(encode()), throwsFormatException);
    info['endpoint'] = 'ws://192.168.3.7:43219/lan';
    info['secret'] = 'bad';
    expect(() => LanTransport.invitation(encode()), throwsFormatException);
    for (final value in [
      'https://example.com/lan',
      'glukwave://lan?data=e30=',
      'glukwave://lan?data=bad',
    ]) {
      expect(() => LanTransport.invitation(value), throwsFormatException);
    }
  });
  test(
    'Real sockets pair, forward to the requesting peer, broadcast and revoke trust',
    () async {
      late LanTransport host, client;
      Json? received;
      var hostSaved = 0, clientSaved = 0;
      host = LanTransport(
        account: 'account-digest',
        deviceId: 'desktop',
        name: 'GlukWave Windows',
        kind: 'windows',
        command: (cmd, args, peer) async => cmd == 'forward'
            ? host.request('play', args, peerId: peer)
            : {'ok': true},
        state: (value) async {},
        changed: () {},
        persist: (value) async {
          hostSaved++;
        },
      );
      client = LanTransport(
        account: 'account-digest',
        deviceId: 'phone',
        name: 'GlukWave Android',
        kind: 'android',
        command: (cmd, args, peer) async => {
          'playing': cmd == 'play',
          'trackId': args['trackId'],
        },
        state: (value) async {
          received = value;
        },
        changed: () {},
        persist: (value) async {
          clientSaved++;
        },
      );
      try {
        await host.start(address: InternetAddress.loopbackIPv4, port: 0);
        await client.start(address: InternetAddress.loopbackIPv4, port: 0);
        final invite = loopback(await host.invite());
        await client.join(invite);
        expect(host.peers.single['online'], true);
        expect(client.connected, true);
        expect(hostSaved, 1);
        expect(clientSaved, 1);
        expect(host.peers.single.containsKey('secret'), false);
        expect(client.peers.single.containsKey('secret'), false);
        expect(await client.request('forward', {'trackId': 'original'}), {
          'playing': true,
          'trackId': 'original',
        });
        await host.broadcast({
          'activeDeviceId': 'phone',
          'state': {'playing': true},
        });
        await eventually(() => received != null);
        expect(received!['activeDeviceId'], 'phone');
        await host.remove('phone');
        await eventually(() => !client.connected);
        expect(host.trust.containsKey('phone'), false);
        expect(hostSaved, 2);
        await expectLater(client.join(invite), throwsA(anything));
        expect(host.trust.containsKey('phone'), false);
      } finally {
        await client.close();
        await host.close();
      }
    },
  );
  test(
    'Account mismatch and device limits are rejected during pairing',
    () async {
      LanTransport make(String id, String account, {int maximum = 3}) =>
          LanTransport(
            account: account,
            deviceId: id,
            name: id,
            kind: 'android',
            maximumPeers: maximum,
            command: (_, __, ___) async => {},
            state: (_) async {},
            changed: () {},
            persist: (_) async {},
          );
      final host = make('host', 'owner', maximum: 2),
          one = make('one', 'owner'),
          two = make('two', 'owner'),
          stranger = make('stranger', 'different');
      try {
        await host.start(address: InternetAddress.loopbackIPv4, port: 0);
        final invitation = loopback(await host.invite());
        await expectLater(stranger.join(invitation), throwsFormatException);
        await one.join(invitation);
        expect(host.trust.length, 1);
        await expectLater(
          two.join(loopback(await host.invite())),
          throwsA(anything),
        );
        expect(host.trust.length, 1);
      } finally {
        await Future.wait([
          one.close(),
          two.close(),
          stranger.close(),
          host.close(),
        ]);
      }
    },
  );
}
