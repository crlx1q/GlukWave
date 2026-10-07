import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/wave_math.dart';
import 'package:glukwave/services/waveform.dart';
import 'package:glukwave/services/ambience.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Flutter Bloom matches actual exported web equations at varied pointer and audio states',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'test/fixtures/wave-math-parity.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(fixture['constants'], {
        'turn': bloomTurn,
        'rest': bloomRest,
        'swell': bloomSwell,
        'cap': bloomCap,
        'reach': bloomReach,
        'phase': bloomPhase,
        'cell': bloomCell,
      });
      for (final point in fixture['points'] as List) {
        final input = point['input'],
            expected = point['expected'],
            pointer = input['pointer'];
        final dot = bloomDot(
          (input['u'] as num).toDouble(),
          (input['v'] as num).toDouble(),
          (input['phase'] as num).toDouble(),
          (input['energy'] as num).toDouble(),
          (pointer['x'] as num).toDouble(),
          (pointer['y'] as num).toDouble(),
          (pointer['active'] as num).toDouble(),
          (input['aspect'] as num).toDouble(),
        );
        expect(dot.level, closeTo(expected['level'] as num, 1e-12));
        expect(dot.radius, closeTo(expected['radius'] as num, 1e-12));
        expect(dot.presence, closeTo(expected['presence'] as num, 1e-12));
      }
      for (final entry in fixture['ease'] as List) {
        expect(
          easeEnergy(
            (entry['current'] as num).toDouble(),
            (entry['target'] as num).toDouble(),
            (entry['seconds'] as num).toDouble(),
          ),
          closeTo(entry['expected'] as num, 1e-12),
        );
      }
    },
  );

  test(
    'Only measured valid envelopes drive energy and pause always silences the response',
    () {
      final measured = AudioEnvelope.fromJson({
        'available': true,
        'duration': 10,
        'samples': [0, .5, 1],
        'source': 'decoded-pcm',
      });
      expect(measured.at(3, true), closeTo(.3, 1e-9));
      expect(measured.at(100, true), 1);
      expect(measured.at(-1, true), 0);
      expect(measured.at(10, false), 0);
      for (final samples in [
        [1.1],
        [-1],
        [double.nan],
        [double.infinity],
        ['.5'],
        List.filled(4097, .5),
      ]) {
        expect(
          AudioEnvelope.fromJson({
            'available': true,
            'duration': 10,
            'samples': samples,
          }).available,
          isFalse,
        );
      }
      expect(
        AudioEnvelope.fromJson({
          'available': false,
          'duration': 10,
          'samples': [.5],
        }).at(5, true),
        0,
      );
    },
  );

  test(
    'Real waveform HTTP response is cached per account and reloads offline',
    () async {
      HttpOverrides.global = null;
      final directory = await Directory.systemTemp.createTemp(
        'glukwave-waveform-',
      );
      final own = await Directory('${directory.path}/own').create(),
          other = await Directory('${directory.path}/other').create();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.uri.path, '/api/tracks/local%3Aone/waveform');
        expect(request.headers.value('authorization'), 'Bearer own-session');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'available': true,
            'duration': 10,
            'samples': [0, .5, 1],
            'source': 'decoded-pcm',
          }),
        );
        await request.response.close();
      });
      final api = WaveApi('http://127.0.0.1:${server.port}')
        ..token = 'own-session';
      final store = WaveformStore(api)..open(own);
      await store.load('local:one');
      expect(store.envelopeFor('local:one').at(3, true), closeTo(.3, 1e-9));
      expect(requests, 1);
      expect(own.listSync().whereType<File>().length, 1);
      store.dispose();
      await server.close(force: true);
      final restored = WaveformStore(api)..open(own);
      await restored.load('local:one');
      expect(restored.envelopeFor('local:one').available, isTrue);
      expect(requests, 1);
      restored.open(other);
      api.token = 'other-session';
      await restored.load('local:one');
      expect(restored.envelopeFor('local:one').available, isFalse);
      expect(other.listSync(), isEmpty);
      restored.dispose();
      api.dio.close(force: true);
      await directory.delete(recursive: true);
    },
  );

  test(
    'A delayed envelope cannot leak into another session, account cache or visible field',
    () async {
      HttpOverrides.global = null;
      final directory = await Directory.systemTemp.createTemp(
        'glukwave-waveform-fence-',
      );
      final own = await Directory('${directory.path}/own').create(),
          other = await Directory('${directory.path}/other').create();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final arrived = Completer<HttpRequest>();
      server.listen((request) {
        arrived.complete(request);
      });
      final api = WaveApi('http://127.0.0.1:${server.port}')
        ..token = 'own-session';
      final store = WaveformStore(api)..open(own);
      final loading = store.load('private');
      final request = await arrived.future;
      api.token = 'other-session';
      store.open(other);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'available': true,
          'duration': 10,
          'samples': [.5, .8],
          'source': 'decoded-pcm',
        }),
      );
      await request.response.close();
      await loading;
      expect(store.envelopeFor('private').available, isFalse);
      expect(own.listSync(), isEmpty);
      expect(other.listSync(), isEmpty);
      store.dispose();
      api.dio.close(force: true);
      await server.close(force: true);
      await directory.delete(recursive: true);
    },
  );

  test(
    'Local rain is decodable non-clipping mono PCM with a continuous loop boundary',
    () {
      final audio = rainPcm();
      final header = ByteData.sublistView(audio);
      expect(ascii.decode(audio.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(audio.sublist(8, 12)), 'WAVE');
      expect(header.getUint32(4, Endian.little), audio.length - 8);
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 22050);
      expect(header.getUint32(40, Endian.little), 22050 * 8 * 2);
      final values = [
        for (var i = 44; i < audio.length; i += 2)
          header.getInt16(i, Endian.little),
      ];
      expect(values.any((sample) => sample.abs() > 100), isTrue);
      expect(values.every((sample) => sample.abs() < 32767), isTrue);
      final peakStep = values
          .asMap()
          .entries
          .where((e) => e.key > 0)
          .map((e) => (e.value - values[e.key - 1]).abs())
          .reduce((a, b) => a > b ? a : b);
      expect((values.first - values.last).abs(), lessThanOrEqualTo(peakStep));
    },
  );
}
