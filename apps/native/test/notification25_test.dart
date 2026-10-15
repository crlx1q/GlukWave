import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/services/audio.dart';
import 'audio_lifecycle_test.dart' as f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        ),
  );

  test(
    'notification heart is selected initially, follows optimistic state and rollback without restarting playback',
    () async {
      final api = f.PlaybackApi(),
          cache = f.PlaybackCache(api),
          output = f.NativeOutput();
      final audio =
          WaveAudioHandler(api, cache, output: output, hardwareVolume: true)
            ..autoCache = false
            ..prepareNext = false;
      var liked = true;
      audio.isNotificationTrackLiked = (_) => liked;
      audio.notificationScope = () => 'account A';
      audio.onNotificationLike = () async {
        liked = !liked;
        audio.refreshNotificationLike();
      };
      try {
        await audio.playTrack(f.external('first'));
        final before = audio.position;
      final loadedBefore = List<String>.from(output.loaded);
        expect(
          audio.playbackState.value.controls.last.androidIcon,
          'drawable/widget_heart_filled',
        );
        expect(audio.mediaItem.value!.rating!.hasHeart(), isTrue);
        final action =
            audio.playbackState.value.controls.last.customAction!.name;
        await audio.customAction(action); // Android hosts need not echo extras.
        expect(liked, isFalse);
        expect(
          audio.playbackState.value.controls.last.androidIcon,
          'drawable/widget_heart',
        );
        expect(audio.mediaItem.value!.rating!.hasHeart(), isFalse);
        liked = true;
        audio.refreshNotificationLike(); // Failed write rolls back locally.
        expect(
          audio.playbackState.value.controls.last.androidIcon,
          'drawable/widget_heart_filled',
        );
        expect(audio.mediaItem.value!.rating!.hasHeart(), isTrue);
        expect(audio.viewCurrent!.id, 'first');
      expect(audio.position, greaterThanOrEqualTo(before));
      expect(output.loaded, loadedBefore);
      } finally {
        await audio.release();
      }
    },
  );

  test(
    'notification action without extras is bound to its actual track and account',
    () async {
      final api = f.PlaybackApi(), cache = f.PlaybackCache(api);
      final audio =
          WaveAudioHandler(
              api,
              cache,
              output: f.NativeOutput(),
              hardwareVolume: true,
            )
            ..autoCache = false
            ..prepareNext = false;
      var scope = 'account A', calls = 0;
      audio.notificationScope = () => scope;
      audio.onNotificationLike = () async {
        calls++;
      };
      try {
        await audio.playTrack(f.external('first'));
        final first =
            audio.playbackState.value.controls.last.customAction!.name;
        await audio.customAction(first);
        expect(calls, 1);
        await audio.playTrack(f.external('second'));
        await audio.customAction(first);
        expect(calls, 1);
        final second =
            audio.playbackState.value.controls.last.customAction!.name;
        scope = 'account B';
        audio.refreshNotificationLike();
        await audio.customAction(second);
        expect(calls, 1);
        await audio.customAction(
          audio.playbackState.value.controls.last.customAction!.name,
        );
        expect(calls, 2);
        await audio.customAction('glukwave.like', {
          'trackId': 'second',
          'scope': 'account A',
        });
        expect(calls, 2);
        await audio.clear();
        expect(
          audio.playbackState.value.controls.any((c) => c.customAction != null),
          isFalse,
        );
      } finally {
        await audio.release();
      }
    },
  );

  test(
    'system heart rating sets intent idempotently and rejects another track or account',
    () async {
      final api = f.PlaybackApi(), cache = f.PlaybackCache(api);
      final audio =
          WaveAudioHandler(
              api,
              cache,
              output: f.NativeOutput(),
              hardwareVolume: true,
            )
            ..autoCache = false
            ..prepareNext = false;
      var liked = false, calls = 0;
      audio.notificationScope = () => 'A';
      audio.isNotificationTrackLiked = (_) => liked;
      audio.onNotificationLike = () async {
        calls++;
        liked = !liked;
        audio.refreshNotificationLike();
      };
      try {
        await audio.playTrack(f.external('first'));
        await audio.setRating(const Rating.newHeartRating(true));
        await audio.setRating(const Rating.newHeartRating(true));
        expect(calls, 1);
        expect(liked, isTrue);
        await audio.setRating(const Rating.newHeartRating(false), {
          'trackId': 'other',
        });
        expect(calls, 1);
        await audio.setRating(const Rating.newHeartRating(false), {
          'scope': 'B',
        });
        expect(calls, 1);
        await audio.setRating(const Rating.newUnratedRating(RatingStyle.heart));
        expect(calls, 1);
        await audio.setRating(const Rating.newHeartRating(false));
        expect(calls, 2);
        expect(liked, isFalse);
      } finally {
        await audio.release();
      }
    },
  );
}
