// Isolated QA data only; never imported by the application.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import '../app_layout_test.dart' show LayoutController;

final qaArtist = <String, dynamic>{'id': 'qa-artist', 'name': 'QA catalogue artist', 'source': 'local', 'artwork': ''};
final qaTrack = <String, dynamic>{'id': 'qa-permitted', 'title': 'A quiet place', 'artist': 'QA catalogue artist', 'duration': 240, 'source': 'local', 'playback': {'kind': 'audio', 'offline': true}};
class ParityApi extends WaveApi {
  final requests = <({String path, String method, Json data})>[];
  Json taste = {'artists': <Json>[], 'onboardingCompleted': false, 'onboardingStep': 0, 'automatic': true, 'revision': 1};
  Json privacy = {'showActivity': false, 'profileStats': true, 'allowFriendRequests': true};
  bool fail = false, owner = false;
  ParityApi() : super('http://127.0.0.1:4000');
  @override Future<Json> call(String path, {String method = 'GET', dynamic data, Json? query}) async {
    requests.add((path: path, method: method, data: object(data)));
    if (fail) throw const WaveException('Unavailable in isolated QA', 'NOT_AVAILABLE', 503);
    final route = Uri.parse(path).path;
    if (route == '/api/taste') { if (method == 'PUT') taste = {...taste, ...object(data)}; return {'taste': taste, 'learnedArtists': []}; }
    if (route == '/api/artists') return {'artists': [qaArtist], 'genres': ['Ambient', 'Electronic']};
    if (route.startsWith('/api/artists/')) return {'artist': qaArtist, 'tracks': [qaTrack]};
    if (route == '/api/recommendations') return {'tracks': [qaTrack], 'artists': [qaArtist], 'genres': ['Ambient'], 'reason': 'taste'};
    if (route == '/api/friends') return {'friends': [{'user': {'id': 'qa-friend', 'username': 'qa_friend', 'displayName': 'QA listener'}, 'online': true, 'activity': {'track': qaTrack, 'jamId': 'qa-jam'}}], 'incoming': [{'id': 'qa-request', 'from': {'id': 'qa-incoming', 'displayName': 'QA invitation', 'username': 'qa_invitation'}}], 'outgoing': []};
    if (route == '/api/users/search') return {'users': [{'id': 'qa-found', 'displayName': 'QA found listener', 'username': 'qa_found', 'relationship': 'none'}]};
    if (route.startsWith('/api/jams/') && route.endsWith('/pause')) return {'connect': {'roomId': 'qa-jam', 'jamPaused': object(data)['paused'], 'outputActive': false}};
    if (route == '/api/account/privacy') { privacy = {...privacy, ...object(data)}; return {'privacy': privacy}; }
    if (route == '/api/account/stats') return {'stats': {'plays': 12, 'listeningSeconds': 1200, 'trackCount': 3, 'artistCount': 2, 'topArtists': [{'name': 'QA catalogue artist', 'plays': 8, 'seconds': 900}], 'topTracks': []}};
    if (route == '/api/admin/registration') return {'registration': {'enabled': true}, 'owner': owner};
    if (route == '/api/admin/overview') return {'counts': {'users': 3, 'tracks': 1}, 'users': [{'id': 'qa-user', 'username': 'qa_user', 'displayName': 'QA listener', 'email': 'qa@example.test', 'role': 'user', 'plan': 'free'}], 'events': []};
    if (route.startsWith('/api/playlists/')) return {'playlist': {'id': 'qa-playlist', 'name': 'Quiet hours', 'trackIds': [qaTrack['id']], 'public': object(data)['public'] == true}, 'tracks': [qaTrack]};
    if (route.endsWith('/lyrics')) return {'lines': []};
    if (route.endsWith('/comments')) return {'comments': []};
    return {'ok': true};
  }
}
class ParityController extends LayoutController {
  ParityController(super.api, super.cache, super.audio);
  @override Future<void> refresh() async {}
}
Future<ParityController> parityController() async {
  SharedPreferences.setMockInitialValues({});
  final api = ParityApi();
  final cache = MusicCache(api);
  final c = ParityController(api, cache, WaveAudioHandler(api, cache));
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true});
  c.loading = false;
  c.online = true;
  c.user = WaveUser({'id': 'qa-owner', 'username': 'qa_owner', 'displayName': 'QA listener', 'email': 'qa_owner@example.test', 'plan': 'beta', 'role': 'admin'});
  c.tracks = [WaveTrack(qaTrack)];
  c.playlists = [{'id': 'qa-playlist', 'name': 'Quiet hours', 'description': 'Isolated QA playlist', 'public': false, 'trackIds': ['qa-permitted'], 'coverArtworks': <String>[]}];
  return c;
}
