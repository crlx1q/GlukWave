import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/ui/motion_icons.dart';
import 'package:glukwave/ui/theme.dart';

void main() {
  Widget transport(bool playing, {bool visible = true, bool reduced = false}) =>
      MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: buildWaveTheme(
          WaveCustomization(reducedMotion: reduced),
          Brightness.light,
        ),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: visible,
            child: Scaffold(
              body: IconButton(
                key: const Key('transport'),
                onPressed: () {},
                icon: WavePlayPauseIcon(playing: playing),
              ),
            ),
          ),
        ),
      );
  testWidgets(
    'Play morph reverses without resizing its hitbox and settles immediately offscreen',
    (tester) async {
      await tester.pumpWidget(transport(false));
      final hitbox = tester.getSize(find.byKey(const Key('transport')));
      expect(hitbox.shortestSide, greaterThanOrEqualTo(48));
      await tester.pumpWidget(transport(true));
      await tester.pump(const Duration(milliseconds: 80));
      final progress = tester
          .widget<AnimatedIcon>(find.byType(AnimatedIcon))
          .progress;
      expect(progress.value, greaterThan(0));
      expect(progress.value, lessThan(1));
      await tester.pumpWidget(transport(false));
      await tester.pump(const Duration(milliseconds: 240));
      expect(progress.value, 0);
      expect(tester.getSize(find.byKey(const Key('transport'))), hitbox);
      await tester.pumpWidget(transport(true, visible: false));
      expect(progress.value, 1);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(transport(false, reduced: true));
      await tester.pump();
      expect(
        tester
            .widget<WavePlayPauseIcon>(find.byType(WavePlayPauseIcon))
            .playing,
        isFalse,
      );
      expect(
        MediaQuery.disableAnimationsOf(
          tester.element(find.byType(WavePlayPauseIcon)),
        ),
        isTrue,
      );
      expect(
        tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value,
        0,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in ['light', 'dark', 'amoled']) {
    testWidgets(
      'Unified $mode slider is touch usable and disabled control does not seek',
      (tester) async {
        final custom = WaveCustomization(theme: mode);
        final theme = buildWaveTheme(
          custom,
          mode == 'light' ? Brightness.light : Brightness.dark,
        );
        double value = .2;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    Slider(
                      key: const Key('seek'),
                      value: value,
                      onChanged: (next) => setState(() => value = next),
                    ),
                    const Slider(
                      key: Key('disabled'),
                      value: .2,
                      onChanged: null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(
          theme.sliderTheme.activeTrackColor,
          theme.extension<WaveVisuals>()!.accent,
        );
        expect(
          theme.sliderTheme.disabledThumbColor,
          isNot(theme.sliderTheme.thumbColor),
        );
        final slider = find.byKey(const Key('seek'));
        expect(tester.getSize(slider).height, greaterThanOrEqualTo(48));
        await tester.tapAt(
          tester.getTopLeft(slider) +
              Offset(tester.getSize(slider).width * .75, 24),
        );
        await tester.pumpAndSettle();
        expect(value, greaterThan(.6));
        final before = value;
        await tester.tap(find.byKey(const Key('disabled')));
        await tester.pumpAndSettle();
        expect(value, before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
