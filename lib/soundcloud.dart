import 'models.dart';

class SoundCloudService {
  const SoundCloudService();

  Uri? resolveTrackUri(Track track) {
    return Uri.tryParse(track.soundCloudUrl);
  }
}
