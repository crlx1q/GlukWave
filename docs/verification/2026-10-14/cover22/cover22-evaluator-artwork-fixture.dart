import 'dart:async';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Genuine decoded project photography through the real network image widget.
/// Only transport is isolated: no owner images or external HTTP are requested.
Future<void> installArtworkFixture() async {
  final bytes = (await rootBundle.load(
    'assets/forest.jpg',
  )).buffer.asUint8List();
  debugNetworkImageHttpClientProvider = () => _ArtworkClient(bytes);
}

void clearArtworkFixture() {
  debugNetworkImageHttpClientProvider = null;
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

class _ArtworkClient implements HttpClient {
  final List<int> bytes;
  _ArtworkClient(this.bytes);
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async => _ArtworkRequest(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ArtworkRequest implements HttpClientRequest {
  final List<int> bytes;
  _ArtworkRequest(this.bytes);
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() async => _ArtworkResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ArtworkResponse extends Stream<List<int>> implements HttpClientResponse {
  final List<int> bytes;
  _ArtworkResponse(this.bytes);
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

