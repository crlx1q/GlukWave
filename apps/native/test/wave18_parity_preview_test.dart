import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/parity.dart';

class PreviewApi extends WaveApi {
  final requests = <Json>[], gates = <Completer<Json>>[];
  PreviewApi() : super('https://isolated.invalid');
  @override
  Future<Json> call(String path,{String method='GET',dynamic data,Json? query}) {
    if(path=='/api/recommendations') {
      requests.add(query!);final gate=Completer<Json>();gates.add(gate);return gate.future;
    }
    return Future.value({});
  }
}
void main() {
  test('Mode and mood preview preserves compatibility and ignores an older result',() async {
    final api=PreviewApi(),parity=WaveParity(api);
    final old=parity.load(mood:'calm');
    final fresh=parity.load(mode:'discovery',mood:'happy');
    expect(api.requests,[{'mood':'calm','mode':'personal'},{'mood':'happy','mode':'discovery'}]);
    api.gates[1].complete({'tracks':<Json>[{'id':'new','title':'New'}]});await fresh;
    expect(parity.tracks.single.id,'new');
    api.gates[0].complete({'tracks':<Json>[{'id':'stale','title':'Stale'}]});await old;
    expect(parity.tracks.single.id,'new');expect(parity.loading,isFalse);
    parity.dispose();api.dio.close(force:true);
  });
}
