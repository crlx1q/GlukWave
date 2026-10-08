import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/services/diagnostics.dart';

void main() {
  test('diagnostics scrub credentials, URLs, emails and local paths', () {
    final clean = scrubDiagnostic(
      'Bearer private-token password=private-password password="private words" mongodb+srv://db-user:db-secret@host.test/data alice@example.test https://host.test/app/?qr=secret-qr C:\\Users\\Alice\\Music\\track.mp3',
    );
    for (final value in [
      'private-token',
      'private-password',
      'alice@example.test',
      'secret-qr',
      'Alice',
      'private words',
      'db-user',
      'db-secret',
    ]) {
      expect(clean, isNot(contains(value)));
    }
  });
  test(
    'real HTTP delivery deduplicates reports and clears the queue after ACK',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <dynamic>[];
      final subscription = server.listen((request) async {
        expect(request.uri.path, '/api/diagnostics/events');
        received.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.statusCode = 202;
        request.response.write('{}');
        await request.response.close();
      });
      final diagnostics = WaveDiagnostics(
        () => 'http://127.0.0.1:${server.port}',
        () => {},
      );
      try {
        diagnostics.report('Test worker failed', kind: 'background');
        diagnostics.report('Test worker failed', kind: 'background');
        await diagnostics.flush();
        await diagnostics.flush();
        expect(received.length, 1);
        expect((received[0]['events'] as List).length, 1);
      } finally {
        diagnostics.dispose();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
